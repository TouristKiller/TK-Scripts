-- @description TK MEDIA BROWSER
-- @author TouristKiller
-- @version 0.1.2:
-- @changelog:
--[[        + Improved: Docking
            + Gui changes
            + Added: Button to open TK FX BROWSER
            
]]--        
--------------------------------------------------------------------------
local r = reaper
local sep = package.config:sub(1,1)
local script_path = debug.getinfo(1, "S").source:match("@?(.*[/\\])")
local peakfiles_path = script_path .. "" .. sep
--local ctx = r.ImGui_CreateContext('TK_MB_' .. reaper.genGuid())
local ctx = r.ImGui_CreateContext('TK Media Browser')
local font_size = 12
local normal_font = reaper.ImGui_CreateFont('sans-serif', font_size)
r.ImGui_Attach(ctx, normal_font)
dock = 0
change_dock = false
local BUTTON_WIDTH = 40
local locations = {}
-- local new_location = ""
local current_location = ""
local selected_location_index = 1
local remember_last_location = false
local current_files = {}
local current_playing_file = ""
local selected_file = ""
local FOLDER_ICON = ""
local FILE_ICON = ""
local playback_state = "stopped"
local preview_track = nil
local auto_play = true
local loop_play = true
local loop_start = 0
local loop_end = 0
local current_pitch = 0
local solo_preview = false
local current_item_length = 0
local use_original_speed = true
local current_playrate = 1.0
local preview_volume = 1.0
local show_preview_in_tcp = false
local mute_preview = false
local disable_fades = true
local is_dragging = false
local drop_file = nil
local drop_track = nil
local is_midi = false
local use_reasynth = false
local use_numa_player = false
local numa_player_installed = false
local pushed_color = false
local is_random_pitch_active = false
local random_pitch_timer = 0
local random_speed = 10 -- standaard waarde
local TKFXB_state = false
-- CF Player
local use_cf_view = false
local CF_Preview = nil
local Play = false
local PlayPos = 0

-- rename
local right_click_location = nil 
local rename_popup_open = false 
local new_name = "" 

-- Browser child variabelen
local file_browser_open = false
local browser_position_left = true
local browser_width = 400 
local browser_height = 500

local dark_gray = 0x303030FF
local hover_gray = 0x606060FF
local active_gray = 0x404040FF

local column1 = 0
local column2 = 80
local column3 = 150
local column4 = 200
local column5 = 220
local PREVIEW_TRACK_NAME = "TK_MEDIA_BROWSER_PREVIEW"

local file_types = {
    -- Audio
    wav = "REAPER_MEDIAFOLDER",
    mp3 = "REAPER_MEDIAFOLDER",
    midi = "REAPER_MEDIAFOLDER",
    mid = "REAPER_MEDIAFOLDER",
    aif = "REAPER_MEDIAFOLDER",
    aiff = "REAPER_MEDIAFOLDER",
    flac = "REAPER_MEDIAFOLDER",
    ogg = "REAPER_MEDIAFOLDER",
    wma = "REAPER_MEDIAFOLDER",
    m4a = "REAPER_MEDIAFOLDER",
    -- Video
    mp4 = "REAPER_VIDEOFOLDER",
    mov = "REAPER_VIDEOFOLDER",
    avi = "REAPER_VIDEOFOLDER",
    wmv = "REAPER_VIDEOFOLDER",
    mkv = "REAPER_VIDEOFOLDER",
    -- Images
    jpg = "REAPER_IMAGEFOLDER",
    jpeg = "REAPER_IMAGEFOLDER",
    png = "REAPER_IMAGEFOLDER",
    gif = "REAPER_IMAGEFOLDER",
    bmp = "REAPER_IMAGEFOLDER"
}

local texture_cache = {}

------------------------------------------------------------------------------------------
-- FUNCTIES
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
end

local function remove_style()
    reaper.ImGui_PopStyleVar(ctx, 3)
    reaper.ImGui_PopStyleColor(ctx, 10)
end


local function serialize(val, name, skipnewlines, depth)
    skipnewlines = skipnewlines or false
    depth = depth or 0

    local tmp = string.rep(" ", depth)

    if name then tmp = tmp .. name .. " = " end

    if type(val) == "table" then
        tmp = tmp .. "{" .. (not skipnewlines and "\n" or "")

        for k, v in pairs(val) do
            tmp =  tmp .. serialize(v, k, skipnewlines, depth + 1) .. "," .. (not skipnewlines and "\n" or "")
        end

        tmp = tmp .. string.rep(" ", depth) .. "}"
    elseif type(val) == "number" then
        tmp = tmp .. tostring(val)
    elseif type(val) == "string" then
        tmp = tmp .. string.format("%q", val)
    elseif type(val) == "boolean" then
        tmp = tmp .. (val and "true" or "false")
    else
        tmp = tmp .. "\"[inserializeable datatype:" .. type(val) .. "]\""
    end

    return tmp
end

local function LoadTexture(path)
    if texture_cache[path] then
        return texture_cache[path]
    end
    
    local source_image = r.JS_LICE_LoadPNG(path)
    if not source_image then return nil end
    
    local orig_width = r.JS_LICE_GetWidth(source_image)
    local orig_height = r.JS_LICE_GetHeight(source_image)
    
    local target_height = 80  -- Vaste hoogte gelijk aan oscilloscoop
    local target_width = math.floor(target_height * (16/9))  -- Breedte berekend op basis van 16:9
    
    local scaled_image = r.JS_LICE_CreateBitmap(true, target_width, target_height)
    
    r.JS_LICE_ScaledBlit(scaled_image, 0, 0, target_width, target_height, 
                         source_image, 0, 0, orig_width, orig_height, 
                         1.0, "QUICKBLIT")
    
    local pixels = {}
    for y = 0, target_height - 1 do
        for x = 0, target_width - 1 do
            local color = r.JS_LICE_GetPixel(scaled_image, x, y)
            table.insert(pixels, color)
        end
    end
    
    r.JS_LICE_DestroyBitmap(source_image)
    r.JS_LICE_DestroyBitmap(scaled_image)
    
    texture_cache[path] = {
        pixels = pixels,
        width = target_width,
        height = target_height
    }
    
    return texture_cache[path]
end

local function save_options()
    local file = io.open(r.GetResourcePath() .. "/Scripts/TK_media_browser_options.txt", "w")
    if file then
        local options = {
            auto_play = auto_play,
            loop_play = loop_play,
            use_original_speed = use_original_speed,
            disable_fades = disable_fades,
            solo_preview = solo_preview,
            mute_preview = mute_preview,
            use_reasynth = use_reasynth,
            use_numa_player = use_numa_player,
            show_preview_in_tcp = show_preview_in_tcp,
            use_cf_view = use_cf_view,
            preview_volume = preview_volume,
            current_db = current_db,
            remember_last_location = remember_last_location,
            last_location_index = selected_location_index
        }
        file:write(serialize(options))
        file:close()
    end
end

local function load_options()
    local file = io.open(r.GetResourcePath() .. "/Scripts/TK_media_browser_options.txt", "r")
    if file then
        local content = file:read("*all")
        local chunk, err = load("return " .. content)
        if chunk then
            local options = chunk()
            auto_play = options.auto_play
            loop_play = options.loop_play
            use_original_speed = options.use_original_speed
            disable_fades = options.disable_fades
            solo_preview = options.solo_preview
            mute_preview = options.mute_preview
            use_reasynth = options.use_reasynth
            use_numa_player = options.use_numa_player
            show_preview_in_tcp = options.show_preview_in_tcp
            use_cf_view = options.use_cf_view
            preview_volume = options.preview_volume
            current_db = options.current_db
            remember_last_location = options.remember_last_location
            
            if remember_last_location and options.last_location_index then
                selected_location_index = options.last_location_index
                current_location = locations[selected_location_index] or ""
                if current_location ~= "" then
                    current_files = read_directory_recursive(current_location)
                end
            end
        end
        file:close()
    end
end
load_options()
local function linear_to_db(linear)
    return 20 * math.log(linear, 10)
end
local function db_to_linear(db)
    return 10 ^ (db / 20)
end
local function generate_peak_file(file_path)
    local file_name = file_path:match("([^/\\]+)$")
    local peak_file_path = peakfiles_path .. file_name .. ".peak"
    
    if not r.file_exists(peak_file_path) then
        local source = r.PCM_Source_CreateFromFile(file_path)
        if source then
            r.PCM_Source_BuildPeaks(source, 0)  -- Gebruik 0 in plaats van peak_file_path
            r.PCM_Source_Destroy(source)
        end
    end
end
local function remove_all_preview_tracks()
    local track_count = r.CountTracks(0)
    for i = track_count - 1, 0, -1 do
        local track = r.GetTrack(0, i)
        local _, track_name = r.GetTrackName(track)
        if track_name == PREVIEW_TRACK_NAME then
            r.DeleteTrack(track)
           
        end
    end
end
local function on_exit()
    save_options()
    if CF_Preview then
        r.CF_Preview_Stop(CF_Preview)
        CF_Preview = nil
    end
    remove_all_preview_tracks()
    r.Main_OnCommand(1016, 0)
    preview_track = nil
end
local function remove_preview_track()
    if preview_track then
        r.DeleteTrack(preview_track)
        --r.Main_OnCommand(40939, 0)
        --r.Main_OnCommand(40297, 0)
        preview_track = nil
    end
end
local function update_pitch()
    if preview_track then
        local item = r.GetTrackMediaItem(preview_track, 0)
        if item then
            local take = r.GetActiveTake(item)
            if take then
                r.SetMediaItemTakeInfo_Value(take, "D_PITCH", current_pitch)
                r.UpdateItemInProject(item)
            end
        end
    end
end

local function check_numa_player_installed()
    local track = r.GetTrack(0, 0)
    if track then
        local fx_index = r.TrackFX_AddByName(track, "Numa Player (Studiologic)", false, -1)
        if fx_index ~= -1 then
            r.TrackFX_Delete(track, fx_index)
            numa_player_installed = true
        else
            numa_player_installed = false
        end
    end
end
local function manage_instruments()
    if preview_track then
        if use_reasynth then
            if r.TrackFX_GetByName(preview_track, "ReaSynth", false) == -1 then
                local fx_index = r.TrackFX_AddByName(preview_track, "ReaSynth", false, -1)
            end
        else
            local fx_index = r.TrackFX_GetByName(preview_track, "ReaSynth", false)
            if fx_index ~= -1 then
                r.TrackFX_Delete(preview_track, fx_index)
            end
        end
        if use_numa_player and numa_player_installed then
            if r.TrackFX_GetByName(preview_track, "Numa Player (Studiologic)", false) == -1 then
                r.TrackFX_AddByName(preview_track, "Numa Player (Studiologic)", false, -1)
            end
        else
            local fx_index = r.TrackFX_GetByName(preview_track, "Numa Player (Studiologic)", false)
            if fx_index ~= -1 then
                r.TrackFX_Delete(preview_track, fx_index)
            end
        end
    end
end
local function position_to_mbt(pos)
    local retval, measures, cml, fullbeats, cdenom = r.TimeMap2_timeToBeats(0, pos)
    local beats = math.floor(fullbeats % cdenom) + 1
    local ticks = math.floor((fullbeats % 1) * 960)
    return measures + 1, beats, ticks
end
local function save_locations()
    local file = io.open(r.GetResourcePath() .. "/Scripts/TK_media_browser_locations.txt", "w")
    if file then
        for _, location in ipairs(locations) do
            file:write(location .. "\n")
        end
        file:close()
    end
end
local function load_locations()
    local file = io.open(r.GetResourcePath() .. "/Scripts/TK_media_browser_locations.txt", "r")
    if file then
        for line in file:lines() do
            table.insert(locations, line)
        end
        file:close()
    end
end
function table.contains(table, element)
    for _, value in pairs(table) do
        if value == element then
            return true
        end
    end
    return false
end
local function read_directory_recursive(path)
    local items = {}
    local i = 0
    while true do
        local subdir = r.EnumerateSubdirectories(path, i)
        if not subdir then break end
        local sub_items = read_directory_recursive(path .. sep .. subdir)
        table.insert(items, {name = subdir, is_dir = true, items = sub_items})
        i = i + 1
    end
    local j = 0
    while true do
        local file = r.EnumerateFiles(path, j)
        if not file then break end
        if file:match("%.wav$") or 
           file:match("%.mp3$") or 
           file:match("%.midi?$") or
           file:match("%.aif[f]?$") or
           file:match("%.flac$") or
           file:match("%.ogg$") or
           file:match("%.wma$") or
           file:match("%.m4a$") or
           -- Afbeeldingsformaten
           file:match("%.jpg$") or
           file:match("%.jpeg$") or
           file:match("%.png$") or
           file:match("%.gif$") or
           file:match("%.bmp$") or
           -- Videoformaten
           file:match("%.mp4$") or
           file:match("%.mov$") or
           file:match("%.avi$") or
           file:match("%.wmv$") or
           file:match("%.mkv$") then
            table.insert(items, {name = file, is_dir = false})
        end
        j = j + 1
    end
    table.sort(items, function(a, b) 
        if a.is_dir == b.is_dir then
            return a.name < b.name
        else
            return a.is_dir
        end
    end)
    return items
end

local function set_track_color(track, color_hex)
    local color = tonumber(color_hex:gsub("#",""), 16)
    r.SetTrackColor(track, color)
end

local function update_playrate(new_playrate)
    current_playrate = new_playrate
    if preview_track then
        local item = r.GetTrackMediaItem(preview_track, 0)
        if item then
            local take = r.GetActiveTake(item)
            if take then
                r.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", current_playrate)
                local source_length = r.GetMediaSourceLength(r.GetMediaItemTake_Source(take))
                local new_length = source_length / current_playrate
                r.SetMediaItemLength(item, new_length, false)
                current_item_length = new_length
                local loop_ratio_start = loop_start / current_item_length
                local loop_ratio_end = loop_end / current_item_length
                loop_start = loop_ratio_start * current_item_length
                loop_end = loop_ratio_end * current_item_length
                r.UpdateItemInProject(item)
                r.GetSet_LoopTimeRange(true, false, 0, new_length, false)
                r.UpdateTimeline()
            end
        end
    end
end
local function play_media(file_path)
    if use_cf_view and not file_path:match("%.midi?$") then  -- Controleer of het geen MIDI-bestand is
        -- CF_Preview code
        if Play then
            r.CF_Preview_Stop(CF_Preview)
            Play = false
            PlayPos = 0
        else
            local source = r.PCM_Source_CreateFromFile(file_path)
            CF_Preview = r.CF_CreatePreview(source)
            
            r.CF_Preview_SetValue(CF_Preview, "D_VOLUME", preview_volume)
            r.CF_Preview_SetValue(CF_Preview, "B_LOOP", loop_play and 1 or 0)
            r.CF_Preview_SetValue(CF_Preview, "D_PITCH", current_pitch)
            
            -- Original Speed toevoegen
            if use_original_speed then
                r.CF_Preview_SetValue(CF_Preview, "D_PLAYRATE", current_playrate)
            else
                -- Tempo matching logica voor CF modus
                local tempo = r.Master_GetTempo()
                local _, rate = r.GetTempoMatchPlayRate(source, 1, 0, 1)
                r.CF_Preview_SetValue(CF_Preview, "D_PLAYRATE", rate)
            end

            if PlayPos > 0 and current_playing_file == file_path then
                r.CF_Preview_SetValue(CF_Preview, "D_POSITION", PlayPos)
            end
            
            r.CF_Preview_Play(CF_Preview)
            Play = true
        end
        current_playing_file = file_path
        playback_state = Play and "playing" or "stopped"
    else
        -- Rest van de play_media functie voor MIDI-bestanden en wanneer CF niet wordt gebruikt
        generate_peak_file(file_path)
        is_midi = file_path:match("%.midi?$") ~= nil
        if not preview_track then
            r.InsertTrackAtIndex(0, false)
            preview_track = r.GetTrack(0, 0)
            r.SetMediaTrackInfo_Value(preview_track, "D_VOL", preview_volume)
            r.SetMediaTrackInfo_Value(preview_track, "B_SHOWINMIXER", 0)
            r.SetMediaTrackInfo_Value(preview_track, "B_SHOWINTCP", 0)
            r.GetSetMediaTrackInfo_String(preview_track, "P_NAME", PREVIEW_TRACK_NAME, true)
            r.SetMediaTrackInfo_Value(preview_track, "I_PERFFLAGS", 3)
            r.SetMediaTrackInfo_Value(preview_track, "I_WNDH", 0)
            r.SetMediaTrackInfo_Value(preview_track, "I_TCPH", 0)
            r.SetMediaTrackInfo_Value(preview_track, "I_MCPW", 0)
        end
        if preview_track then
            set_track_color(preview_track, "#0000FF")
        end
        r.SetOnlyTrackSelected(preview_track)
        r.SetMediaTrackInfo_Value(preview_track, "B_MUTE", mute_preview and 1 or 0)
        r.SetMediaTrackInfo_Value(preview_track, "D_VOL", preview_volume)
        r.SetMediaTrackInfo_Value(preview_track, "I_SOLO", solo_preview and 1 or 0)
        r.SetMediaTrackInfo_Value(preview_track, "B_SHOWINTCP", show_preview_in_tcp and 1 or 0)
        local item = r.GetTrackMediaItem(preview_track, 0)
        if item then
            local item_length = r.GetMediaItemInfo_Value(item, "D_LENGTH")
            loop_start = 0
            loop_end = item_length
        end
        while r.GetTrackNumMediaItems(preview_track) > 0 do
            local item = r.GetTrackMediaItem(preview_track, 0)
            r.DeleteTrackMediaItem(preview_track, item)
        end
        local item = r.AddMediaItemToTrack(preview_track)
        local take = r.AddTakeToMediaItem(item)
        r.SetMediaItemTake_Source(take, r.PCM_Source_CreateFromFile(file_path))
        r.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", current_playrate)
        r.SetMediaItemPosition(item, 0, false)
        if disable_fades then
            r.SetMediaItemInfo_Value(item, "D_FADEINLEN", 0)
            r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", 0)
            r.SetMediaItemInfo_Value(item, "C_FADEINSHAPE", 0)
            r.SetMediaItemInfo_Value(item, "C_FADEOUTSHAPE", 0)
        end
        if is_midi then
            local source_length = r.GetMediaSourceLength(r.GetMediaItemTake_Source(take))
            local tempo = r.Master_GetTempo()
            local beats_length = (source_length / 60) * tempo
            current_item_length = use_original_speed and source_length or (beats_length * (60 / tempo))
            -- Halveer de lengte voor MIDI-bestanden
            current_item_length = current_item_length / 2
        else
            if use_original_speed then
                current_item_length = r.GetMediaSourceLength(r.GetMediaItemTake_Source(take))
                r.SetMediaItemTakeInfo_Value(take, 'D_PLAYRATE', 1)
                current_playrate = 1
            else
                local pos = 0
                local _, rate, len = r.GetTempoMatchPlayRate(r.GetMediaItemTake_Source(take), 1, pos, 1)
                r.SetMediaItemTakeInfo_Value(take, 'D_PLAYRATE', rate)
                current_item_length = len
            end
        end
        r.SetMediaItemLength(item, current_item_length, false)
        r.GetSet_LoopTimeRange(true, false, 0, current_item_length, false)
        r.Main_OnCommand(40044, 0)
        if loop_play then
            r.GetSetRepeat(1)
        else
            r.GetSetRepeat(0)
        end
        r.SetEditCurPos(0, false, false)
        r.OnPlayButton()
        current_playing_file = file_path
        playback_state = "playing"
        manage_instruments()  -- Zorg ervoor dat instrumenten correct worden beheerd
    end
end

local function pause_playback()
    if use_cf_view and CF_Preview then
        local retval
        retval, PlayPos = r.CF_Preview_GetValue(CF_Preview, "D_POSITION")
        r.CF_Preview_Stop(CF_Preview)
        Play = false
        playback_state = "paused"
    else
        r.Main_OnCommand(40073, 0)
        playback_state = "paused"
    end
end
local function stop_playback()
    if use_cf_view and CF_Preview then
        r.CF_Preview_Stop(CF_Preview)
        Play = false
        PlayPos = 0
        playback_state = "stopped"
    else
    r.Main_OnCommand(1016, 0)
    playback_state = "stopped"
    remove_preview_track()
    
    audio_buffer = {} -- Reset de audio-buffer
    -- Reset de instrumenten
    use_reasynth = false
    use_numa_player = false
    end
end
local function update_loop_positions()
    if use_original_speed and preview_track then
        local item = r.GetTrackMediaItem(preview_track, 0)
        if item then
            local item_length = r.GetMediaItemInfo_Value(item, "D_LENGTH")
            loop_start = loop_start * (current_item_length / item_length)
            loop_end = loop_end * (current_item_length / item_length)
        end
    end
end
local function interpolate_color(progress)
    local r = 0
    local g = 0
    local b = 0
    
    progress = math.max(0, math.min(1, progress))
    
    if progress < 0.5 then
        r = math.floor(255 * (progress * 2))
        g = 255
    else
        r = 255
        g = math.floor(255 * (1 - (progress - 0.5) * 2))
    end
    
    -- Zorg ervoor dat alle waarden geldige integers zijn
    r = math.floor(math.max(0, math.min(255, r)))
    g = math.floor(math.max(0, math.min(255, g)))
    
    return (r << 24) | (g << 16) | (b << 8) | 0xFF
end




local function draw_playback_position()
    if current_playing_file ~= "" then
        if use_cf_view and CF_Preview then
            local retval, pos = r.CF_Preview_GetValue(CF_Preview, "D_POSITION")
            local retval2, length = r.CF_Preview_GetValue(CF_Preview, "D_LENGTH")
            
            -- Als pos of length nil zijn (bij stop/pauze), zet ze op 0
            pos = pos or 0
            length = length or 1  -- Voorkom delen door 0
            
            local width = r.ImGui_GetContentRegionAvail(ctx) - 5
            local height = 20
            local draw_list = r.ImGui_GetWindowDrawList(ctx)
            local x, y = r.ImGui_GetCursorScreenPos(ctx)
            
            r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, 0x333333FF)
            local progress = math.min(pos / length, 1)
            local color = interpolate_color(progress)
            r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width * progress, y + height, color)
            
            local time_text = string.format("%.2f / %.2f", pos, length)
            local m, b, t = position_to_mbt(pos)
            local mbt_text = string.format("%d.%d.%03d", m, b, t)
            r.ImGui_DrawList_AddText(draw_list, x + 5, y + 5, 0xFFFFFFFF, time_text .. " - " .. mbt_text)
            r.ImGui_Dummy(ctx, width, height)
        else
            if current_item_length > 0 then
                local pos = r.GetPlayPosition()
                local width = r.ImGui_GetWindowWidth(ctx)
                local height = 20
                local draw_list = r.ImGui_GetWindowDrawList(ctx)
                local x, y = r.ImGui_GetCursorScreenPos(ctx)
                r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, 0x333333FF)
                local progress = math.min(pos / current_item_length, 1)
                local color = interpolate_color(progress)
                r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width * progress, y + height, color)
                local time_text = string.format("%.2f / %.2f", pos, current_item_length)
                local m, b, t = position_to_mbt(pos)
                local mbt_text = string.format("%d.%d.%03d", m, b, t)
                r.ImGui_DrawList_AddText(draw_list, x + 5, y + 5, 0xFFFFFFFF, time_text .. " - " .. mbt_text)
                r.ImGui_Dummy(ctx, width, height)
            end
        end
    end
end
local function handle_drag_drop(file_path)
    if r.ImGui_BeginDragDropSource(ctx, r.ImGui_DragDropFlags_SourceAllowNullID()) then
        drop_file = file_path
        r.ImGui_SetDragDropPayload(ctx, "REAPER_MEDIAFOLDER", file_path)
        r.ImGui_Text(ctx, "Drag to Track: " .. file_path)
        r.ImGui_EndDragDropSource(ctx)
    end
end
local function insert_media_on_track(file_path, track, use_original_speed, custom_playrate, custom_pitch)
    if not track then return end
    
    local ext = file_path:match("%.([^%.]+)$"):lower()
    local file_type = file_types[ext]
    local item = r.AddMediaItemToTrack(track)
    
    if file_type == "REAPER_MEDIAFOLDER" then
        -- Audio/midi logica
        local take = r.AddTakeToMediaItem(item)
        local source = r.PCM_Source_CreateFromFile(file_path)
        r.SetMediaItemTake_Source(take, source)
        local cursor_pos = r.GetCursorPosition()
        r.SetMediaItemPosition(item, cursor_pos, false)
        local source_length = r.GetMediaSourceLength(source)
        if use_original_speed then
            r.SetMediaItemLength(item, source_length / custom_playrate, false)
            r.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", custom_playrate)
        else
            local _, rate, len = r.GetTempoMatchPlayRate(source, 1, 0, 1)
            r.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", rate)
            r.SetMediaItemLength(item, len, false)
        end
        r.SetMediaItemTakeInfo_Value(take, "D_PITCH", custom_pitch)
    elseif file_type == "REAPER_IMAGEFOLDER" or file_type == "REAPER_VIDEOFOLDER" then
        -- Video/Image logica
        local take = r.AddTakeToMediaItem(item)
        r.SetMediaItemTake_Source(take, r.PCM_Source_CreateFromFile(file_path))
        local cursor_pos = r.GetCursorPosition()
        r.SetMediaItemPosition(item, cursor_pos, false)
        r.SetMediaItemLength(item, 5.0, false)
    end
    
    if disable_fades then
        r.SetMediaItemInfo_Value(item, "D_FADEINLEN", 0)
        r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", 0)
        r.SetMediaItemInfo_Value(item, "C_FADEINSHAPE", 0)
        r.SetMediaItemInfo_Value(item, "C_FADEOUTSHAPE", 0)
    end
    
    r.UpdateItemInProject(item)
    r.UpdateTimeline()
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
end


local function handle_reaper_drop()
    local mouse_state = r.JS_Mouse_GetState(1)
    if mouse_state == 1 and drop_file then
        is_dragging = true
        drop_track = r.GetTrackFromPoint(r.GetMousePosition())
    elseif mouse_state == 0 and is_dragging then
        if drop_file and drop_track then
            insert_media_on_track(drop_file, drop_track, use_original_speed, current_playrate, current_pitch)
        else
            r.ShowConsoleMsg("Drop file or track is nil\n")
        end
        is_dragging = false
        drop_file = nil
        drop_track = nil
    end
end

local function get_audio_file_info(file_path)
    local source = r.PCM_Source_CreateFromFile(file_path)
    if not source then return nil end
    local sample_rate = r.GetMediaSourceSampleRate(source)
    local num_channels = r.GetMediaSourceNumChannels(source)
    local length = r.GetMediaSourceLength(source)
    return {
        sample_rate = sample_rate,
        num_channels = num_channels,
        length = length
    }
end

local audio_buffer = {}
local buffer_size = 1024

local function get_audio_data()
    if use_cf_view and CF_Preview then
        local retval, pos = r.CF_Preview_GetValue(CF_Preview, "D_POSITION")
        local source = r.PCM_Source_CreateFromFile(current_playing_file)
        if source then
            local samplerate = r.GetMediaSourceSampleRate(source)
            local samplebuffer = r.new_array(buffer_size * 2)
            r.PCM_Source_GetPeaks(source, samplerate, pos, 1, buffer_size, 0, samplebuffer)
            for i = 1, buffer_size do
                audio_buffer[i] = samplebuffer[i*2-1] or 0
            end
        end
    else
        if not preview_track then return end
        local item = r.GetTrackMediaItem(preview_track, 0)
        if not item then return end
        local take = r.GetActiveTake(item)
        if not take then return end
        local source = r.GetMediaItemTake_Source(take)
        if not source then return end
        local playpos = r.GetPlayPosition()
        local samplerate = r.GetMediaSourceSampleRate(source)
        local accessor = r.CreateTakeAudioAccessor(take)
        local samplebuffer = r.new_array(buffer_size * 2)
        r.GetAudioAccessorSamples(accessor, samplerate, 1, playpos, buffer_size, samplebuffer)
        for i = 1, buffer_size do
            audio_buffer[i] = samplebuffer[i*2-1] or 0
        end
        r.DestroyAudioAccessor(accessor)
    end
end


--------------------------------------------------------------------------------------------
-- FUNCTIE VOOR FILE BROWSER VENSTER
local function draw_file_browser()
    local main_pos_x, main_pos_y = r.ImGui_GetWindowPos(ctx)
    local main_width, _ = r.ImGui_GetWindowSize(ctx)
    
    local browser_x = browser_position_left and (main_pos_x - browser_width) or (main_pos_x + main_width)
    r.ImGui_SetNextWindowPos(ctx, browser_x, main_pos_y)
    r.ImGui_SetNextWindowSizeConstraints(ctx, 300, 280, 1000, 1000)
    reaper.ImGui_SetNextWindowBgAlpha(ctx, 0.9)
    
    local window_flags = r.ImGui_WindowFlags_NoMove() | r.ImGui_WindowFlags_NoCollapse() | r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoTitleBar()
    
    if r.ImGui_Begin(ctx, 'File Browser', true, window_flags) then
        local new_width = r.ImGui_GetWindowWidth(ctx)
        local new_height = r.ImGui_GetWindowHeight(ctx)
        if new_width ~= browser_width or new_height ~= browser_height then
            if browser_position_left then
                local delta = new_width - browser_width
                r.ImGui_SetWindowPos(ctx, browser_x - delta, main_pos_y)
            end
            browser_width = new_width
            browser_height = new_height
        end
   
        if current_location ~= "" then
            r.ImGui_Text(ctx, "".. current_location)
            r.ImGui_Separator(ctx)

            local child_flags = r.ImGui_WindowFlags_HorizontalScrollbar() | r.ImGui_WindowFlags_NoBackground()
            if r.ImGui_BeginChild(ctx, "file_list", 0, -80, 1, child_flags) then
                local function display_tree(items, path)
                    for _, item in ipairs(items) do
                        local icon = item.is_dir and FOLDER_ICON or FILE_ICON
                        if item.is_dir then
                            local tree_open = r.ImGui_TreeNode(ctx, icon .. " " .. item.name)
                            r.ImGui_SameLine(ctx)
                            if r.ImGui_Button(ctx, "+##" .. path .. sep .. item.name) then
                                local full_path = path .. sep .. item.name
                                if not table.contains(locations, full_path) then
                                    table.insert(locations, full_path)
                                    save_locations()
                                end
                            end
                            if tree_open then
                                display_tree(item.items, path .. sep .. item.name)
                                r.ImGui_TreePop(ctx)
                            end
                        else
                            if item.name == selected_file then
                                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFFFF00FF)
                                pushed_color = true
                            end
                            if r.ImGui_Selectable(ctx, icon .. " " .. item.name, item.name == selected_file) then
                                local file_path = path .. sep .. item.name
                                if auto_play then
                                    if current_playing_file == file_path and Play then
                                        stop_playback()
                                    else
                                        selected_file = item.name
                                        current_playing_file = file_path
                                        play_media(file_path)
                                    end
                                else
                                    selected_file = item.name
                                    current_playing_file = file_path
                                end
                            end
                            if pushed_color then
                                r.ImGui_PopStyleColor(ctx)
                                pushed_color = false
                            end
        
                            handle_drag_drop(path .. sep .. item.name)
                        end
                    end
                end

                display_tree(current_files, current_location)
                r.ImGui_EndChild(ctx)
            end
            if current_playing_file ~= "" and not current_playing_file:match("%.midi?$") then
                local info = get_audio_file_info(current_playing_file)
                if info then
                    r.ImGui_Separator(ctx)
                    local file_name = current_playing_file:match("([^/\\]+)$")
                    r.ImGui_Text(ctx, "" .. file_name)
                    r.ImGui_Text(ctx, "Sample rate: " .. info.sample_rate .. " Hz")
                    r.ImGui_Text(ctx, "Channels: " .. info.num_channels)
                    r.ImGui_Text(ctx, "Length: " .. string.format("%.2f", info.length) .. " seconden")
                    r.ImGui_Dummy(ctx, 0, 20)
                end
            end
        end
        r.ImGui_End(ctx)
    end
end

local function handleDocking()
    if change_dock then
        r.ImGui_SetNextWindowDockID(ctx, ~dock)
        change_dock = false
    end
end

--------------------------------------------------------------------
-- MAIN LOOP
local function loop()
    if not ctx or not r.ImGui_ValidatePtr(ctx, 'ImGui_Context*') then
        ctx = r.ImGui_CreateContext('TK Media Browser')
        normal_font = r.ImGui_CreateFont('sans-serif', font_size)
        r.ImGui_Attach(ctx, normal_font)
     
    end
    handleDocking()
    apply_style()
    r.ImGui_PushFont(ctx, normal_font)
    reaper.ImGui_SetNextWindowBgAlpha(ctx, 0.9)
    reaper.ImGui_SetNextWindowSizeConstraints(ctx, 140, 285, 16384, 16384)
    
    local visible, open = r.ImGui_Begin(ctx, 'TK Media Browser', true, r.ImGui_WindowFlags_NoTitleBar())
    dock = r.ImGui_GetWindowDockID(ctx)
    if visible then
        local total_available_width = reaper.ImGui_GetContentRegionAvail(ctx)
        local spacing = reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing())
        local button_width = (total_available_width - (spacing * (5 - 1))) / 5
        if r.ImGui_Button(ctx, file_browser_open and "C" or "O", button_width) then
            file_browser_open = not file_browser_open
        end
        reaper.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, browser_position_left and "L" or "R", button_width) then
            browser_position_left = not browser_position_left
        end
        reaper.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, TKFXB_state and "FX" or "FX", button_width) then
            TKFXB_state = not TKFXB_state
            r.Main_OnCommand(reaper.NamedCommandLookup("_RSf7ad518475afabaca1169de44f70a95c8f933ddc"), 0)
        end
        reaper.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "D", button_width) then
            change_dock = true    
        end

        r.ImGui_SameLine(ctx)
        local window_width = reaper.ImGui_GetWindowWidth(ctx)
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xFF0000FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xFF5555FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0xFF0000FF)
        if reaper.ImGui_Button(ctx, 'Q', button_width) then
            open = false
        end
        reaper.ImGui_PopStyleColor(ctx, 3)
        local total_width = reaper.ImGui_GetContentRegionAvail(ctx)
        local spacing = reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing())
        local slider_width = total_width - BUTTON_WIDTH - spacing

        local ADD_BUTTON_SIZE = 18
        r.ImGui_SetNextItemWidth(ctx, -ADD_BUTTON_SIZE - spacing)
        if r.ImGui_BeginCombo(ctx, "##Locations", locations[selected_location_index] or "Select...") then
               
            for i, location in ipairs(locations) do
                local is_selected = (i == selected_location_index)

                -- Detecteer rechtermuisklik en sla de locatie op
                if r.ImGui_Selectable(ctx, location, is_selected, r.ImGui_SelectableFlags_AllowDoubleClick()) then
                    if r.ImGui_IsMouseClicked(ctx, 1) then
                        right_click_location = location
                        r.ImGui_OpenPopup(ctx, "LocationContextMenu")
                    else
                        selected_location_index = i
                        current_location = location
                        current_files = read_directory_recursive(location)
                    end
                end
        
                if r.ImGui_BeginPopupContextItem(ctx) then
                    if r.ImGui_MenuItem(ctx, "Open in Explorer/Finder") then
                        local full_path = locations[selected_location_index] -- Zorg ervoor dat 'location' het volledige pad bevat
                        local command
                        if reaper.GetOS():match("Win") then
                            -- Gebruik dubbele backslashes voor Windows-paden
                            full_path = full_path:gsub("/", "\\")
                            command = string.format('explorer "%s"', full_path)
                        else
                            command = string.format('open "%s"', full_path)
                        end
                        
                        os.execute(command)
                    end
                    
                    if r.ImGui_MenuItem(ctx, "Move Up") and i > 1 then
                        locations[i], locations[i-1] = locations[i-1], locations[i]
                        save_locations()
                    end
                    
                    if r.ImGui_MenuItem(ctx, "Move Down") and i < #locations then
                        locations[i], locations[i+1] = locations[i+1], locations[i]
                        save_locations()
                    end
                    
                    
                    if r.ImGui_MenuItem(ctx, "Remove") then
                        table.remove(locations, i)
                        save_locations()
                        if i == selected_location_index then
                            selected_location_index = 1
                            current_location = locations[1] or ""
                            current_files = current_location ~= "" and read_directory_recursive(current_location) or {}
                        end
                    end
                    r.ImGui_EndPopup(ctx)
                end
                
                if is_selected then
                    r.ImGui_SetItemDefaultFocus(ctx)
                end
            end
            r.ImGui_EndCombo(ctx)
        end
        
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "+", ADD_BUTTON_SIZE, ADD_BUTTON_SIZE) then
            local retval, folder = r.JS_Dialog_BrowseForFolder(0, "Select Folder", "")
            if retval and folder ~= "" then
                if not table.contains(locations, folder) then
                    table.insert(locations, folder)
                    save_locations()
                end
            end
        end
         
        local combo_flags = r.ImGui_ComboFlags_HeightLargest()

        r.ImGui_SetNextItemWidth(ctx, -1)
        if r.ImGui_BeginCombo(ctx, "##Options", "Options", combo_flags) then
            
            local check_color = 0x808080FF -- grijs
            if use_cf_view then
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), check_color)
                r.ImGui_Text(ctx, "v")
                r.ImGui_PopStyleColor(ctx)
                r.ImGui_SameLine(ctx)
            else
                r.ImGui_Dummy(ctx, 12, 0)
                r.ImGui_SameLine(ctx)
            end
            if r.ImGui_Selectable(ctx, "Use CF Engine", use_cf_view) then
                use_cf_view = not use_cf_view
                stop_playback() -- Stop huidige playback voordat we van engine wisselen
            end
            -- Remember Last Location
            if remember_last_location then
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), check_color)
                r.ImGui_Text(ctx, "v")
                r.ImGui_PopStyleColor(ctx)
                r.ImGui_SameLine(ctx)
            else
                r.ImGui_Dummy(ctx, 12, 0)
                r.ImGui_SameLine(ctx)
            end
            if r.ImGui_Selectable(ctx, "Remember Last Location", remember_last_location) then
                remember_last_location = not remember_last_location
            end
            
            -- Auto Play
            if auto_play then
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), check_color)
                r.ImGui_Text(ctx, "v")
                r.ImGui_PopStyleColor(ctx)
                r.ImGui_SameLine(ctx)
            else
                r.ImGui_Dummy(ctx, 12, 0)
                r.ImGui_SameLine(ctx)
            end
            if r.ImGui_Selectable(ctx, "Auto Play", auto_play) then
                auto_play = not auto_play
            end
        
            -- Loop
            if loop_play then
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), check_color)
                r.ImGui_Text(ctx, "v")
                r.ImGui_PopStyleColor(ctx)
                r.ImGui_SameLine(ctx)
            else
                r.ImGui_Dummy(ctx, 12, 0)
                r.ImGui_SameLine(ctx)
            end
            if r.ImGui_Selectable(ctx, "Loop", loop_play) then
                loop_play = not loop_play
                if current_playing_file ~= "" then
                    play_media(current_playing_file)
                end
            end
        
            -- OG Speed
            r.ImGui_BeginDisabled(ctx, is_midi)
            if use_original_speed then
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), check_color)
                r.ImGui_Text(ctx, "v")
                r.ImGui_PopStyleColor(ctx)
                r.ImGui_SameLine(ctx)
            else
                r.ImGui_Dummy(ctx, 12, 0)
                r.ImGui_SameLine(ctx)
            end
            if r.ImGui_Selectable(ctx, "OG Speed", use_original_speed) then
                use_original_speed = not use_original_speed
                if current_playing_file ~= "" then
                    play_media(current_playing_file)
                end
            end
            r.ImGui_EndDisabled(ctx)
        
            -- No Fade
            if disable_fades then
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), check_color)
                r.ImGui_Text(ctx, "v")
                r.ImGui_PopStyleColor(ctx)
                r.ImGui_SameLine(ctx)
            else
                r.ImGui_Dummy(ctx, 12, 0)
                r.ImGui_SameLine(ctx)
            end
            if r.ImGui_Selectable(ctx, "No Fade", disable_fades) then
                disable_fades = not disable_fades
                if preview_track then
                    local item = r.GetTrackMediaItem(preview_track, 0)
                    if item then
                        if disable_fades then
                            r.SetMediaItemInfo_Value(item, "D_FADEINLEN", 0)
                            r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", 0)
                            r.SetMediaItemInfo_Value(item, "C_FADEINSHAPE", 0)
                            r.SetMediaItemInfo_Value(item, "C_FADEOUTSHAPE", 0)
                        else
                            local default_fadein = r.SNM_GetIntConfigVar("defsplitfadeinlen", 0) / 1000
                            local default_fadeout = r.SNM_GetIntConfigVar("defsplitfadeoutlen", 0) / 1000
                            r.SetMediaItemInfo_Value(item, "D_FADEINLEN", default_fadein)
                            r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", default_fadeout)
                            r.SetMediaItemInfo_Value(item, "C_FADEINSHAPE", 0)
                            r.SetMediaItemInfo_Value(item, "C_FADEOUTSHAPE", 0)
                        end
                        r.UpdateItemInProject(item)
                    end
                end
            end
        
            -- Solo
            if solo_preview then
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), check_color)
                r.ImGui_Text(ctx, "v")
                r.ImGui_PopStyleColor(ctx)
                r.ImGui_SameLine(ctx)
            else
                r.ImGui_Dummy(ctx, 12, 0)
                r.ImGui_SameLine(ctx)
            end
            if r.ImGui_Selectable(ctx, "Solo", solo_preview) then
                solo_preview = not solo_preview
                if preview_track then
                    r.SetMediaTrackInfo_Value(preview_track, "I_SOLO", solo_preview and 1 or 0)
                end
            end
        
            -- Mute
            if mute_preview then
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), check_color)
                r.ImGui_Text(ctx, "v")
                r.ImGui_PopStyleColor(ctx)
                r.ImGui_SameLine(ctx)
            else
                r.ImGui_Dummy(ctx, 12, 0)
                r.ImGui_SameLine(ctx)
            end
            if r.ImGui_Selectable(ctx, "Mute", mute_preview) then
                mute_preview = not mute_preview
                if preview_track then
                    r.SetMediaTrackInfo_Value(preview_track, "B_MUTE", mute_preview and 1 or 0)
                end
            end
        
            -- ReaSynth
            if use_reasynth then
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), check_color)
                r.ImGui_Text(ctx, "v")
                r.ImGui_PopStyleColor(ctx)
                r.ImGui_SameLine(ctx)
            else
                r.ImGui_Dummy(ctx, 12, 0)
                r.ImGui_SameLine(ctx)
            end
            if r.ImGui_Selectable(ctx, "ReaSynth", use_reasynth) then
                use_reasynth = not use_reasynth
                manage_instruments()
            end
        
            -- Numa Player (indien geïnstalleerd)
            if numa_player_installed then
                if use_numa_player then
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), check_color)
                    r.ImGui_Text(ctx, "v")
                    r.ImGui_PopStyleColor(ctx)
                    r.ImGui_SameLine(ctx)
                else
                    r.ImGui_Dummy(ctx, 12, 0)
                    r.ImGui_SameLine(ctx)
                end
                if r.ImGui_Selectable(ctx, "Numa Player", use_numa_player) then
                    use_numa_player = not use_numa_player
                    manage_instruments()
                end
            end
        
            -- Preview Track
            if show_preview_in_tcp then
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), check_color)
                r.ImGui_Text(ctx, "v")
                r.ImGui_PopStyleColor(ctx)
                r.ImGui_SameLine(ctx)
            else
                r.ImGui_Dummy(ctx, 12, 0)
                r.ImGui_SameLine(ctx)
            end
            if r.ImGui_Selectable(ctx, "Preview Track", show_preview_in_tcp) then
                show_preview_in_tcp = not show_preview_in_tcp
                if preview_track then
                    r.SetMediaTrackInfo_Value(preview_track, "B_SHOWINTCP", show_preview_in_tcp and 1 or 0)
                    r.TrackList_AdjustWindows(false)
                end
            end
        
            r.ImGui_EndCombo(ctx)
        end
        r.ImGui_Separator(ctx)
        draw_playback_position()

            -- Oscilloscoop/Preview tekenen
            if current_playing_file ~= "" then
                local ext = current_playing_file:match("%.([^%.]+)$"):lower()
                local file_type = file_types[ext]
                
                if file_type == "REAPER_IMAGEFOLDER" or file_type == "REAPER_VIDEOFOLDER" then
                    local texture = LoadTexture(current_playing_file)
                    if texture then
                        local draw_list = r.ImGui_GetWindowDrawList(ctx)
                        local pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
                        local width = r.ImGui_GetContentRegionAvail(ctx)
                        local height = 80
                        
                        for i, color in ipairs(texture.pixels) do
                            local x = (i-1) % texture.width
                            local y = math.floor((i-1) / texture.width)
                            
                            local blue = color & 0xFF
                            local green = (color >> 8) & 0xFF
                            local red = (color >> 16) & 0xFF
                            local alpha = (color >> 24) & 0xFF
                            local imgui_color = r.ImGui_ColorConvertDouble4ToU32(red/255, green/255, blue/255, alpha/255)
                            
                            r.ImGui_DrawList_AddRectFilled(draw_list, 
                                pos_x + x, 
                                pos_y + y, 
                                pos_x + x + 1, 
                                pos_y + y + 1, 
                                imgui_color)
                        end
                        r.ImGui_Dummy(ctx, texture.width, texture.height)
                    end
                else
                    if (preview_track and not is_midi) or (use_cf_view and CF_Preview) then
                        get_audio_data()
                        local draw_list = r.ImGui_GetWindowDrawList(ctx)
                        local pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
                        local width = r.ImGui_GetContentRegionAvail(ctx)
                        local height = 80
                        r.ImGui_DrawList_AddRect(draw_list, pos_x, pos_y, pos_x + width, pos_y + height, 0x000000FF)
                
                        if #audio_buffer > 0 then
                            for i = 1, math.floor(buffer_size/2) - 1 do
                                local x1 = pos_x + (i-1) * width / (buffer_size/2)
                                local y1 = pos_y + height/2 + (audio_buffer[i] or 0) * height/2
                                local x2 = pos_x + i * width / (buffer_size/2)
                                local y2 = pos_y + height/2 + (audio_buffer[i+1] or 0) * height/2
                                r.ImGui_DrawList_AddLine(draw_list, x1, y1, x2, y2, 0x00FF00FF, 1)
                            end
                        else
                            r.ImGui_DrawList_AddLine(draw_list, pos_x, pos_y + height/2, pos_x + width, pos_y + height/2, 0x00FF00FF, 1)
                        end
                
                        r.ImGui_Dummy(ctx, width, height)
                    end
                end
            end

            r.ImGui_PushItemWidth(ctx, slider_width)
            local current_db = linear_to_db(preview_volume) 
            local rv, new_db = r.ImGui_SliderDouble(ctx, "##Volume", current_db, -60, 12, "%.1f dB")
            r.ImGui_PopItemWidth(ctx)

            r.ImGui_SameLine(ctx)

            if r.ImGui_Button(ctx, "0dB", BUTTON_WIDTH) then
                new_db = 0
                rv = true
            end

            if rv then 
                current_db = new_db
                preview_volume = db_to_linear(current_db)
                if preview_track then
                    r.SetMediaTrackInfo_Value(preview_track, "D_VOL", preview_volume)
                end
                if use_cf_view and CF_Preview then
                    r.CF_Preview_SetValue(CF_Preview, "D_VOLUME", preview_volume)
                end
            end


            -- Playrate slider
            r.ImGui_PushItemWidth(ctx, slider_width)
            r.ImGui_BeginDisabled(ctx, is_midi or not use_original_speed)
            local rv_playrate, new_playrate = r.ImGui_SliderDouble(ctx, "##Playrate", current_playrate, 0.1, 2.0, "%.2f")
            r.ImGui_EndDisabled(ctx)
            r.ImGui_PopItemWidth(ctx)

            r.ImGui_SameLine(ctx)
            r.ImGui_BeginDisabled(ctx, not use_original_speed)
            if r.ImGui_Button(ctx, "Reset", BUTTON_WIDTH) then
                new_playrate = 1.0
                rv_playrate = true
            end
            r.ImGui_EndDisabled(ctx)

            if rv_playrate and use_original_speed then
                current_playrate = new_playrate
                if use_cf_view and CF_Preview then
                    r.CF_Preview_SetValue(CF_Preview, "D_PLAYRATE", current_playrate)
                else
                    if preview_track then
                        local item = r.GetTrackMediaItem(preview_track, 0)
                        if item then
                            local take = r.GetActiveTake(item)
                            if take then
                                r.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", current_playrate)
                                local source_length = r.GetMediaSourceLength(r.GetMediaItemTake_Source(take))
                                local new_length = source_length / current_playrate
                                r.SetMediaItemLength(item, new_length, false)
                                current_item_length = new_length
                                local loop_ratio_start = loop_start / current_item_length
                                local loop_ratio_end = loop_end / current_item_length
                                loop_start = loop_ratio_start * current_item_length
                                loop_end = loop_ratio_end * current_item_length
                                r.UpdateItemInProject(item)
                                r.GetSet_LoopTimeRange(true, false, 0, new_length, false)
                                r.UpdateTimeline()
                            end
                        end
                    end
                end
            end          
            --Pitch slider en random knop
            r.ImGui_PushItemWidth(ctx, slider_width)

            -- Maak de frames kleiner met FramePadding
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 0, 0)
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 3, 3)
            -- Onthoud de startpositie voor de random knop
            local start_pos_y = r.ImGui_GetCursorPosY(ctx)

            local rv_pitch, new_pitch = r.ImGui_SliderInt(ctx, "##Pitch", current_pitch, -12, 12, "%d semitones")
            local rv_speed, new_speed = r.ImGui_SliderInt(ctx, "##Random Speed", random_speed, 10, 300, "Speed: %d")

            -- Bereken de totale hoogte van beide sliders
            local total_height = r.ImGui_GetCursorPosY(ctx) - start_pos_y - 3

            -- Positioneer de random knop
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosY(ctx, start_pos_y)
            if r.ImGui_Button(ctx, is_random_pitch_active and "Stop" or "Rand", BUTTON_WIDTH, total_height) then
                is_random_pitch_active = not is_random_pitch_active
                if not is_random_pitch_active then
                    new_pitch = 0
                    rv_pitch = true
                end
            end

            r.ImGui_PopStyleVar(ctx, 2)
            r.ImGui_PopItemWidth(ctx)

            -- Update de random speed als de slider wordt aangepast
            if rv_speed then
                random_speed = new_speed
            end
            if rv_pitch or is_random_pitch_active then
                current_pitch = new_pitch
                if use_cf_view and CF_Preview then
                    r.CF_Preview_SetValue(CF_Preview, "D_PITCH", current_pitch)
                else
                    update_pitch()
                end
            end
            
            if is_random_pitch_active then
                random_pitch_timer = random_pitch_timer + 1
                if random_pitch_timer >= random_speed then
                    current_pitch = math.random(-12, 12)
                    if use_cf_view and CF_Preview then
                        r.CF_Preview_SetValue(CF_Preview, "D_PITCH", current_pitch)
                    else
                        update_pitch()
                    end
                    random_pitch_timer = 0
                end
            end

            local window_height = r.ImGui_GetWindowHeight(ctx)
            local play_button_width = (total_available_width - (spacing * (3 - 1))) / 3
            r.ImGui_SetCursorPosY(ctx, window_height - 30)  

            r.ImGui_Separator(ctx)

            -- Play knop
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00AA00FF)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x00CC00FF)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x008800FF)
            if r.ImGui_Button(ctx, "|>", play_button_width) and current_playing_file ~= "" then
                play_media(current_playing_file)
            end
            r.ImGui_PopStyleColor(ctx, 3)

            -- Pause knop
            r.ImGui_SameLine(ctx)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xFFA500FF)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xFFB52EFF)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xE69400FF)
            if r.ImGui_Button(ctx, "| |", play_button_width) then
                pause_playback()
            end
            r.ImGui_PopStyleColor(ctx, 3)

            -- Stop knop
            r.ImGui_SameLine(ctx)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xFF0000FF)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xFF3333FF)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xCC0000FF)
            if r.ImGui_Button(ctx, "[]", play_button_width) then
                stop_playback()
            end
            r.ImGui_PopStyleColor(ctx, 3)



            
            if file_browser_open then
                draw_file_browser()
            end
            remove_style()
            r.ImGui_End(ctx)

    end
    
    r.ImGui_PopFont(ctx)
    handle_reaper_drop()
    if open then
        r.defer(loop)
    else
        on_exit()
    end
end
local function exit_script()
    save_options()
    on_exit()
end
r.atexit(exit_script)
load_locations()
check_numa_player_installed()
if remember_last_location and selected_location_index > 0 then
    current_location = locations[selected_location_index]
    if current_location then
        current_files = read_directory_recursive(current_location)
    end
end
r.defer(loop)
