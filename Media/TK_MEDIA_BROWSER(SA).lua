-- @description TK MEDIA BROWSER
-- @author TouristKiller
-- @version 0.6.5
-- @changelog:
--[[       

]]--        
--------------------------------------------------------------------------
local r = reaper
local sep = package.config:sub(1,1)
local script_path = debug.getinfo(1, "S").source:match("@?(.*[/\\])")
local peakfiles_path = script_path .. "" .. sep
local json_path = script_path .. "json_tkmb.lua"
local json = dofile(json_path)
local cache_dir = script_path .. "CACHE" .. sep
local collections_dir = script_path .. "COLLECTIONS" .. sep
local presets_dir = script_path .. "PRESETS" .. sep
local settings_image_path = script_path .. "TKMBSETTINGS.png"
r.RecursiveCreateDirectory(cache_dir, 0)
r.RecursiveCreateDirectory(collections_dir, 0)
r.RecursiveCreateDirectory(presets_dir, 0)
local ctx = r.ImGui_CreateContext('TK Media Browser')
local font_size = 13
local medium_font_size = 11  
local small_font_size = 9

local normal_font = nil
local medium_font = nil
local small_font = nil

ImGui_Knob_drag_y = ImGui_Knob_drag_y or {}
local BUTTON_WIDTH = 40

-- Playback State
local playback = {
    current_playing_file = "",
    selected_file = "",
    last_displayed_file = "",
    is_paused = false,
    paused_position = 0,
    playing_source = nil,
    playing_preview = nil,
    playing_path = nil,
    state = "stopped",
    auto_play = true,
    loop_play = true,
    loop_start = 0,
    loop_end = 0,
    current_pitch = 0,
    current_playrate = 1.0,
    effective_playrate = 1.0,
    preview_volume = 1.0,
    use_original_speed = true,
    link_transport = false,
    link_start_from_editcursor = false,
    last_transport_state = 0,
    speed_manually_changed = false,
    prev_play_cursor = nil,
    pending_sync_refresh = false,
    last_sync_reference = nil,
    video_preview_track = nil,
    video_preview_item = nil,
    is_video_playback = false,
    is_midi_playback = false,
    saved_solo_states = {},
    use_exclusive_solo = true  
}

-- File & Location Management
local file_location = {
    locations = {},
    current_location = "",
    selected_location_index = 1,
    remember_last_location = true,
    current_files = {},
    collections = {},
    selected_collection = nil,
    last_folder_location = "",
    last_folder_index = 1,
    last_collection_name = nil,
    selected_files = {},
    last_selected_index = nil,
    flat_view = false,
    saved_folder_flat_view = false,
    collection_restored = false,
    selected_category = "All",
    show_category_manager = false,
    new_category_name = "",
    custom_folder_names = {},  
    custom_folder_colors = {},
    custom_collection_colors = {},
    rename_popup_location = nil,
    rename_popup_initialized = false,
    renaming_location = nil,
    renaming_initialized = false,
    renaming_collection = nil,
    renaming_collection_initialized = false
}

-- Waveform & Visualization
local waveform = {
    cache = {},
    cache_file = "",
    oscilloscope_cache = {},
    oscilloscope_cache_file = "",
    spectral_cache = {},
    spectral_cache_file = "",
    show_spectral_view = false,
    midi_notes = {},
    midi_notes_file = "",
    midi_length = 0,
    midi_info_message = nil,  
    selection_start = 0,
    selection_end = 0,
    is_dragging = false,
    selection_active = false,
    monitor_sel_start = 0,
    monitor_sel_end = 0,
    monitor_file_path = "",
    normalized_sel_start = 0,
    normalized_sel_end = 0,
    grid_overlay = false,
    play_cursor_position = 0,  
    cached_length = 0,
    cached_length_file = "",
    zoom_level = 1.0,  
    scroll_offset = 0.0, 
    vertical_zoom = 1.0,
    current_pitch_hz = nil,
    current_pitch_note = nil,
    last_pitch_update = 0,
    pitch_history = {},  -- For smoothing
    stable_pitch_timer = 0,  -- Timer for how long pitch has been stable
}

-- UI State & View Control
local ui = {
    window_x = 100,
    window_y = 100,
    remember_window_position = true,
    position_applied = false,
    last_move_time = 0,
    visible_files = {},
    selected_index = 1,
    show_oscilloscope = true,
    waveform_grid_overlay = false,
    show_collection_section = false,
    current_view_mode = "folders",  
    list_clipper = nil,
    scroll_to_top = false,
    pitch_detection_enabled = true
}

-- Available fonts (cross-platform compatible)
local available_fonts = {
    "Arial",
    "Consolas",
    "Courier New",
    "Georgia",
    "Helvetica",
    "Roboto",
    "Times New Roman",
    "Trebuchet MS",
    "Verdana",
    "Comic Sans MS",
    "Impact",
    "Lucida Console",
    "Tahoma"
}

local font_objects = {}  

-- Search & Filter
local search_filter = {
    search_history = {},
    max_search_history = 10,
    search_term = "",
    filtered_files = {},
    cached_flat_files = {},
    cached_location = "",
    last_sort_column = -1,
    last_sort_direction = 0,
    sorted_files = {}
}

local function clear_sort_cache()
    search_filter.sorted_files = {}
    search_filter.last_sort_column = -1
    search_filter.last_sort_direction = 0
end

-- Cache Management
local cache_mgmt = {
    scan_message = "",
    message_timer = nil,
    loading_files = false,
    scan_progress = 0,
    last_scan_time = 0,
    total_files = 0,
    processed_files = 0,
    show_progress = false
}

local cached_metadata = {}

-- Drag & Drop / Insert
local insert_state = {
    current_item_length = 0,
    current_item_start = 0,
    disable_fades = true,
    is_dragging = false,
    drop_file = nil,
    drop_track = nil,
    is_midi = false
}

-- Plugin/Tool State
local plugin_state = {
    use_reasynth = false,
    use_numa_player = false,
    numa_player_installed = false,
    is_random_pitch_active = false,
    random_pitch_timer = 0,
    random_speed = 10,
    TKFXB_state = false
}

-- UI Settings & Appearance
local ui_settings = {
    -- Layout & Dimensions
    BASE_HEIGHT = 110,
    OSCILLOSCOPE_HEIGHT = 60,
    SLIDERS_HEIGHT = 78,
    browser_width = 400,
    browser_height = 530,
    column1 = 0,
    column2 = 80,
    column3 = 150,
    column4 = 200,
    column5 = 220,
    
    file_browser_open = false,
    browser_position_left = true,
    right_click_location = nil,
    rename_popup_open = false,
    new_name = "",
    rename_inline_text = "",
    
    dark_gray = 0x303030FF,
    hover_gray = 0x606060FF,
    active_gray = 0x404040FF,
    light_gray = 0xA0A0A0FF,
    
    window_bg_brightness = 0.12,
    window_opacity = 0.94,
    text_brightness = 1.0,
    grid_brightness = 1.0,
    button_brightness = 0.25,
    button_text_brightness = 1.0,
    waveform_hue = 0.55,
    waveform_thickness = 1.0,
    waveform_resolution_multiplier = 2.0,
    accent_hue = 0.55,
    selection_hue = 0.16,
    selection_saturation = 1.0,
    show_waveform_bg = true,
    hide_scrollbar = false,  
    selected_font = "Arial",  
    button_height = 25,
    use_numaplayer = false,
    numaplayer_preset = "",
    use_selected_track_for_midi = false,
    
    pushed_color = 0,
    audio_buffer = {},
    buffer_size = 2048,
    last_audio_update = 0,
    
    visible_columns = {
        name = true,
        type = true,
        size = true,
        duration = true,
        sample_rate = true,
        channels = true,
        bpm = true,
        key = true,
        artist = false,
        album = false,
        title = false,
        track = false,
        year = false,
        genre = false,
        comment = false,
        composer = false,
        publisher = false,
        timesignature = false,
        bitrate = false,
        bitspersample = false,
        encoder = false,
        copyright = false,
        desc = false,
        originator = false,
        originatorref = false,
        date = false,
        time = false,
        umid = false
    }
}

local FOLDER_ICON = ""
local FILE_ICON = ""
local file_types = {
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
    mp4 = "REAPER_VIDEOFOLDER",
    mov = "REAPER_VIDEOFOLDER",
    avi = "REAPER_VIDEOFOLDER",
    wmv = "REAPER_VIDEOFOLDER",
    mkv = "REAPER_VIDEOFOLDER",
    gif = "REAPER_VIDEOFOLDER",  
    jpg = "REAPER_IMAGEFOLDER",
    jpeg = "REAPER_IMAGEFOLDER",
    png = "REAPER_IMAGEFOLDER",
    bmp = "REAPER_IMAGEFOLDER"
}
local texture_cache = {}

local function hsv_to_color(hue, saturation, value, alpha)
    saturation = saturation or 1.0
    value = value or 1.0
    alpha = alpha or 1.0
    
    local red, green, blue
    local i = math.floor(hue * 6)
    local f = hue * 6 - i
    local p = value * (1 - saturation)
    local q = value * (1 - f * saturation)
    local t = value * (1 - (1 - f) * saturation)
    
    i = i % 6
    if i == 0 then red, green, blue = value, t, p
    elseif i == 1 then red, green, blue = q, value, p
    elseif i == 2 then red, green, blue = p, value, t
    elseif i == 3 then red, green, blue = p, q, value
    elseif i == 4 then red, green, blue = t, p, value
    else red, green, blue = value, p, q
    end
    
    return r.ImGui_ColorConvertDouble4ToU32(red, green, blue, alpha)
end

local function rgb_to_hsv(r, g, b)
    local max = math.max(r, g, b)
    local min = math.min(r, g, b)
    local h, s, v = 0, 0, max
    
    local d = max - min
    s = max == 0 and 0 or d / max
    
    if max == min then
        h = 0
    else
        if max == r then
            h = (g - b) / d + (g < b and 6 or 0)
        elseif max == g then
            h = (b - r) / d + 2
        else
            h = (r - g) / d + 4
        end
        h = h / 6
    end
    
    return h, s, v
end

local function get_font(font_name, size)
    local key = font_name .. "_" .. tostring(size)
    if not font_objects[key] then
        font_objects[key] = r.ImGui_CreateFont(font_name, size)
        r.ImGui_Attach(ctx, font_objects[key])
    end
    return font_objects[key]
end

local function update_fonts()
    normal_font = get_font(ui_settings.selected_font, font_size)
    medium_font = get_font(ui_settings.selected_font, medium_font_size)
    small_font = get_font(ui_settings.selected_font, small_font_size)
end

local video_image_extensions = {
    mp4 = true, mov = true, avi = true, wmv = true, mkv = true,
    mpg = true, mpeg = true, flv = true, webm = true, m4v = true,
    gif = true, jpg = true, jpeg = true, png = true, bmp = true
}

local function is_video_or_image_file(filename)
    local ext = string.lower(string.match(filename, "%.([^%.]+)$") or "")
    return video_image_extensions[ext] or false
end

local function detect_pitch_autocorrelation(audio_buffer, sample_rate)
    if not audio_buffer or #audio_buffer < 200 then
        waveform.pitch_debug = "Buf too small"
        return nil
    end

    local energy = 0
    for i = 1, #audio_buffer do
        energy = energy + audio_buffer[i] * audio_buffer[i]
    end
    energy = math.sqrt(energy / #audio_buffer)

    if energy < 0.02 then
        waveform.pitch_debug = string.format("Silence (%.4f)", energy)
        return nil
    end

    local min_freq = 40
    local max_freq = 1200

    local min_period = math.floor(sample_rate / max_freq)
    local max_period = math.min(math.floor(sample_rate / min_freq), math.floor(#audio_buffer / 3))

    local best_correlation = -1
    local best_period = 0
    local samples_to_check = math.min(#audio_buffer - max_period, 2048)

    for period = min_period, max_period, 1 do
        local sum_diff = 0
        local count = 0

        for i = 1, samples_to_check do
            if i + period <= #audio_buffer then
                sum_diff = sum_diff + math.abs(audio_buffer[i] - audio_buffer[i + period])
                count = count + 1
            end
        end

        if count > 0 then
            local avg_diff = sum_diff / count
            local correlation = 1 - avg_diff

            if correlation > best_correlation then
                best_correlation = correlation
                best_period = period
            end
        end
    end

    if best_period > min_period and best_period < max_period then
        local sum_diff_prev = 0
        local count_prev = 0
        for i = 1, samples_to_check do
            if i + best_period - 1 <= #audio_buffer then
                sum_diff_prev = sum_diff_prev + math.abs(audio_buffer[i] - audio_buffer[i + best_period - 1])
                count_prev = count_prev + 1
            end
        end
        local prev_corr = count_prev > 0 and (1 - sum_diff_prev / count_prev) or -1

        local sum_diff_next = 0
        local count_next = 0
        for i = 1, samples_to_check do
            if i + best_period + 1 <= #audio_buffer then
                sum_diff_next = sum_diff_next + math.abs(audio_buffer[i] - audio_buffer[i + best_period + 1])
                count_next = count_next + 1
            end
        end
        local next_corr = count_next > 0 and (1 - sum_diff_next / count_next) or -1
    end

    local energy_threshold = 0.55 - (energy - 0.02) * 2
    energy_threshold = math.max(0.3, math.min(0.7, energy_threshold))

    if best_period > 0 and best_correlation > energy_threshold then
        local frequency = sample_rate / best_period
        frequency = frequency / 2

        if frequency >= min_freq and frequency <= max_freq then
            waveform.pitch_debug = string.format("SR:%.0f C:%.3f E:%.3f T:%.1f P:%.1f F:%.0f", sample_rate, best_correlation, energy, energy_threshold, best_period, frequency)
            return frequency
        end
    end

    waveform.pitch_debug = string.format("Low C:%.3f", best_correlation)
    return nil
end

local function freq_to_note(freq)
    if not freq or freq <= 0 then
        return nil
    end

    local note_names = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}

    local a4 = 440.0

    local c0 = a4 * (2 ^ -4.75)

    local half_steps = 12 * (math.log(freq / c0) / math.log(2))

    local note_index = math.floor((half_steps % 12) + 0.5) % 12 + 1
    local octave = math.floor(half_steps / 12)

    if octave < 0 or octave > 9 then
        return nil
    end

    return note_names[note_index] .. octave
end

local function get_meta_first(source, keys)
    for _, key in ipairs(keys) do
        local retval, value = r.GetMediaFileMetadata(source, key)
        if retval and value and value ~= "" then
            return value
        end
    end
    return nil
end

-- Get script version from metadata
local script_version = "0.0.0"
local function get_script_version()
    if script_version ~= "0.0.0" then
        return script_version
    end
    
    -- Read from current file to extract version
    local script_file = debug.getinfo(1, "S").source:match("@?(.*)")
    if script_file then
        local file = io.open(script_file, "r")
        if file then
            for line in file:lines() do
                local version = line:match("^%-%-%s*@version%s+(.+)")
                if version then
                    script_version = version:gsub("%s+", "")
                    file:close()
                    return script_version
                end
                -- Stop after first 10 lines (metadata should be at top)
                if line:match("^%-%-%-%-") or line:match("^local ") then
                    break
                end
            end
            file:close()
        end
    end
    return script_version
end

-- Initialize version on load
script_version = get_script_version()

local function load_midi_notes(file_path)
    local notes = {}
    local midi_length = 0
    local temp_track = r.GetTrack(0, 0)
    if temp_track then
        local num_items_before = r.CountTrackMediaItems(temp_track)
        local temp_item = r.AddMediaItemToTrack(temp_track)
        if temp_item then
            local take = r.AddTakeToMediaItem(temp_item)
            if take then
                local source = r.PCM_Source_CreateFromFile(file_path)
                if source then
                    r.SetMediaItemTake_Source(take, source)
                    local length = r.GetMediaSourceLength(source)
                    if length and length > 0 then
                        r.SetMediaItemLength(temp_item, length, false)
                        r.UpdateItemInProject(temp_item)
                        
                        local retval, notecnt = r.MIDI_CountEvts(take)
                        if retval and notecnt > 0 then
                            for i = 0, notecnt - 1 do
                                local retval, selected, muted, startppq, endppq, chan, pitch, vel = r.MIDI_GetNote(take, i)
                                if retval then
                                    local start_time = r.MIDI_GetProjTimeFromPPQPos(take, startppq)
                                    local end_time = r.MIDI_GetProjTimeFromPPQPos(take, endppq)
                                    table.insert(notes, {
                                        start = start_time,
                                        end_time = end_time,
                                        pitch = pitch,
                                        velocity = vel,
                                        channel = chan
                                    })
                                end
                            end
                        end
                    end
                end
            end
            r.DeleteTrackMediaItem(temp_track, temp_item)
        end
    end
    return notes, midi_length
end

local function get_file_metadata(file_path)
    local metadata = {
        name = file_path:match("([^/\\]+)$") or "",
        type = "",
        size = "",
        size_bytes = 0,
        duration = "",
        duration_seconds = 0,
        sample_rate = "",
        sample_rate_hz = 0,
        channels = "",
        channels_num = 0,
        bpm = "",
        bpm_num = 0,
        key = "",
        artist = "",
        album = "",
        title = "",
        track = "",
        year = "",
        genre = "",
        comment = "",
        composer = "",
        publisher = "",
        timesignature = "",
        bitrate = "",
        bitrate_num = 0,
        bitspersample = "",
        bitspersample_num = 0,
        encoder = "",
        copyright = "",
        desc = "",
        originator = "",
        originatorref = "",
        date = "",
        time = "",
        umid = ""
    }
    local ext = string.lower(string.match(file_path, "%.([^%.]+)$") or "")
    
    metadata.type = ext:upper()
    
    local file = io.open(file_path, "rb")
    if file then
        local size_bytes = file:seek("end")
        file:close()
        if size_bytes then
            metadata.size_bytes = size_bytes
            if size_bytes < 1024 then
                metadata.size = string.format("%d B", size_bytes)
            elseif size_bytes < 1024 * 1024 then
                metadata.size = string.format("%.1f KB", size_bytes / 1024)
            elseif size_bytes < 1024 * 1024 * 1024 then
                metadata.size = string.format("%.1f MB", size_bytes / (1024 * 1024))
            else
                metadata.size = string.format("%.2f GB", size_bytes / (1024 * 1024 * 1024))
            end
        end
    end
    local video_exts = {mp4=true, mov=true, avi=true, wmv=true, mkv=true, mpg=true, mpeg=true, flv=true, webm=true, m4v=true}
    local image_exts = {gif=true, jpg=true, jpeg=true, png=true, bmp=true}
    local is_video = video_exts[ext] or false
    local is_image = image_exts[ext] or false
    
    if is_video then
        local source = r.PCM_Source_CreateFromFile(file_path)
        if source then
            local length = r.GetMediaSourceLength(source)
            if length then
                metadata.duration_seconds = length
                if length < 60 then
                    metadata.duration = string.format("%.2fs", length)
                else
                    local mins = math.floor(length / 60)
                    local secs = math.floor(length % 60)
                    metadata.duration = string.format("%d:%02d", mins, secs)
                end
            end
            r.PCM_Source_Destroy(source)
        end
        for key in pairs(metadata) do
            if key ~= "name" and key ~= "type" and key ~= "size" and 
               key ~= "duration" and key ~= "duration_seconds" and 
               key ~= "size_bytes" and type(metadata[key]) == "string" then
                metadata[key] = "--"
            end
        end
    elseif is_image then
        for key in pairs(metadata) do
            if key ~= "name" and key ~= "type" and key ~= "size" and 
               key ~= "size_bytes" and type(metadata[key]) == "string" then
                metadata[key] = "--"
            end
        end
    else
        local source = r.PCM_Source_CreateFromFile(file_path)
        if source then
            local length = r.GetMediaSourceLength(source)
            
            local is_midi_file = (ext == "mid" or ext == "midi")
            if is_midi_file and length then
                length = length / 2
            end
            
            local sr = r.GetMediaSourceSampleRate(source)
            local ch = r.GetMediaSourceNumChannels(source)
            
            if length then
                metadata.duration_seconds = length  
                if length < 60 then
                    metadata.duration = string.format("%.2fs", length)
                else
                    local mins = math.floor(length / 60)
                    local secs = math.floor(length % 60)
                    metadata.duration = string.format("%d:%02d", mins, secs)
                end
            end
            
            if sr then
                metadata.sample_rate_hz = sr  
                metadata.sample_rate = string.format("%.0f", sr / 1000) .. "k"
            end
            
            if ch then
                metadata.channels_num = ch  
                metadata.channels = ch == 1 and "Mono" or (ch == 2 and "Stereo" or tostring(ch))
            end
            
            local bpm_str = get_meta_first(source, {"XMP:dm/tempo", "ID3:TBPM", "VORBIS:BPM", "RIFF:ACID:tempo", "tempo"})
            if bpm_str then
                local bpm_val = tonumber(bpm_str) or 0
                metadata.bpm_num = bpm_val
                metadata.bpm = string.format("%.0f", bpm_val)
            end
            
            local key_str = get_meta_first(source, {"XMP:dm/key", "ID3:TKEY", "RIFF:IKEY", "VORBIS:KEY", "RIFF:ACID:key", "key"})
            if key_str then
                metadata.key = key_str
            end
            
            local artist_str = get_meta_first(source, {"ID3:TPE1", "VORBIS:ARTIST", "RIFF:IART", "XMP:dm/artist", "artist"})
            if artist_str then
                metadata.artist = artist_str
            end
            
            local album_str = get_meta_first(source, {"ID3:TALB", "VORBIS:ALBUM", "RIFF:IPRD", "XMP:dm/album", "album"})
            if album_str then
                metadata.album = album_str
            end
            
            local title_str = get_meta_first(source, {"ID3:TIT2", "VORBIS:TITLE", "RIFF:INAM", "XMP:dc/title", "title"})
            if title_str then
                metadata.title = title_str
            end
            
            local track_str = get_meta_first(source, {"ID3:TRCK", "VORBIS:TRACKNUMBER", "RIFF:IPRT", "track"})
            if track_str then
                metadata.track = track_str
            end
            
            local year_str = get_meta_first(source, {"ID3:TDRC", "ID3:TYER", "VORBIS:DATE", "RIFF:ICRD", "year"})
            if year_str then
                metadata.year = year_str
            end
            
            local genre_str = get_meta_first(source, {"XMP:dm/genre", "ID3:TCON", "VORBIS:GENRE", "RIFF:IGNR", "genre"})
            if genre_str then
                metadata.genre = genre_str
            end
            
            local comment_str = get_meta_first(source, {"XMP:dm/logComment", "ID3:COMM", "VORBIS:COMMENT", "RIFF:ICMT", "comment"})
            if comment_str then
                metadata.comment = comment_str
            end
            
            local composer_str = get_meta_first(source, {"ID3:TCOM", "VORBIS:COMPOSER", "RIFF:IMUS", "composer"})
            if composer_str then
                metadata.composer = composer_str
            end
            
            local publisher_str = get_meta_first(source, {"ID3:TPUB", "VORBIS:PUBLISHER", "publisher"})
            if publisher_str then
                metadata.publisher = publisher_str
            end
            
            local timesig_str = get_meta_first(source, {"ID3:TSIG", "VORBIS:TIMESIGNATURE", "timesignature"})
            if timesig_str then
                metadata.timesignature = timesig_str
            end
            
            local bitrate_str = get_meta_first(source, {"bitrate"})
            if bitrate_str then
                local bitrate_val = tonumber(bitrate_str) or 0
                metadata.bitrate_num = bitrate_val
                metadata.bitrate = string.format("%.0f", bitrate_val / 1000) .. "k"
            end
            
            local bps_str = get_meta_first(source, {"bitspersample"})
            if bps_str then
                local bps_val = tonumber(bps_str) or 0
                metadata.bitspersample_num = bps_val
                metadata.bitspersample = bps_val .. "-bit"
            end
            
            local encoder_str = get_meta_first(source, {"ID3:TENC", "VORBIS:ENCODER", "RIFF:ISFT", "encoder"})
            if encoder_str then
                metadata.encoder = encoder_str
            end
            
            local copyright_str = get_meta_first(source, {"ID3:TCOP", "VORBIS:COPYRIGHT", "RIFF:ICOP", "copyright"})
            if copyright_str then
                metadata.copyright = copyright_str
            end
            
            local desc_str = get_meta_first(source, {"BWF:Description", "RIFF:IDESC", "RIFF:ICMT", "desc"})
            if desc_str then
                metadata.desc = desc_str
            end
            
            local orig_str = get_meta_first(source, {"BWF:Originator", "originator"})
            if orig_str then
                metadata.originator = orig_str
            end
            
            local origref_str = get_meta_first(source, {"BWF:OriginatorReference", "originatorref"})
            if origref_str then
                metadata.originatorref = origref_str
            end
            
            local date_str = get_meta_first(source, {"BWF:OriginationDate", "XMP:xmp/CreateDate", "ID3:TDRC", "VORBIS:DATE", "RIFF:ICRD", "date"})
            if date_str then
                metadata.date = date_str
            end
            
            local time_str = get_meta_first(source, {"BWF:OriginationTime", "time"})
            if time_str then
                metadata.time = time_str
            end
            
            local umid_str = get_meta_first(source, {"BWF:UMID", "umid"})
            if umid_str then
                metadata.umid = umid_str
            end
            
            r.PCM_Source_Destroy(source)
        end
    end
    
    return metadata
end

local function save_file_cache_progressive(location, files, start_index)
    if start_index > #files then
        local cache_file = cache_dir .. "file_cache_" .. location:gsub("[^%w]", "_") .. ".json"
        local file_timestamps = {}
        local has_js_api = reaper.JS_Dialog_BrowseForSaveFile ~= nil
        
        if has_js_api then
            for _, file in ipairs(files) do
                if file.full_path then
                    local retval, size, mtime = reaper.JS_File_Stat(file.full_path)
                    if retval then
                        file_timestamps[file.full_path] = mtime
                    end
                end
            end
        end
                
        local data = {
            location = location,
            files = files,
            cache_time = os.time(),
            file_count = #files,
            file_timestamps = file_timestamps,
            file_metadata = cached_metadata
        }
        local json_str = json.encode(data)
        local file = io.open(cache_file, "w")
        if file then
            file:write(json_str)
            file:close()
        end
        
        cache_mgmt.loading_files = false
        cache_mgmt.show_progress = false
        cache_mgmt.scan_message = string.format("Done! %d files found", #files)
        cache_mgmt.message_timer = os.time()
        
        search_filter.cached_flat_files = files
        search_filter.cached_location = location
        search_filter.filtered_files = files
        return
    end
    
    local batch_size = 5
    local end_index = math.min(start_index + batch_size - 1, #files)
    
    for i = start_index, end_index do
        local file = files[i]
        if file.full_path and not is_video_or_image_file(file.full_path) then
            local meta = get_file_metadata(file.full_path)
            cached_metadata[file.full_path] = meta
            cache_mgmt.processed_files = cache_mgmt.processed_files + 1
        end
    end
    
    r.defer(function()
        save_file_cache_progressive(location, files, end_index + 1)
    end)
end

local function save_file_cache(location, files)
    local cache_file = cache_dir .. "file_cache_" .. location:gsub("[^%w]", "_") .. ".json"
    
    local file_timestamps = {}
    local file_metadata = {}
    local has_js_api = reaper.JS_Dialog_BrowseForSaveFile ~= nil
    
    if has_js_api then
        for _, file in ipairs(files) do
            if file.full_path then
                local retval, size, mtime = reaper.JS_File_Stat(file.full_path)
                if retval then
                    file_timestamps[file.full_path] = mtime
                end
            end
        end
        for _, file in ipairs(files) do
            if file.full_path then
                if not is_video_or_image_file(file.full_path) then
                    local meta = get_file_metadata(file.full_path)
                    file_metadata[file.full_path] = meta
                    cache_mgmt.processed_files = cache_mgmt.processed_files + 1
                end
            end
        end
    end
    
    local data = {
        location = location,
        files = files,
        cache_time = os.time(),
        file_count = #files,
        file_timestamps = file_timestamps,
        file_metadata = file_metadata
    }
    local json_str = json.encode(data)
    local file = io.open(cache_file, "w")
    if file then
        file:write(json_str)
        file:close()
        return true
    end
    return false
end

local function save_file_cache_with_timestamps(location, files, old_timestamps, old_metadata)
    local cache_file = cache_dir .. "file_cache_" .. location:gsub("[^%w]", "_") .. ".json"
    
    local file_timestamps = {}
    local file_metadata = {}
    local has_js_api = reaper.JS_Dialog_BrowseForSaveFile ~= nil
    
    if has_js_api then
        for _, file in ipairs(files) do
            if file.full_path then
                if old_timestamps and old_timestamps[file.full_path] then
                    file_timestamps[file.full_path] = old_timestamps[file.full_path]
                else
                    local retval, size, mtime = reaper.JS_File_Stat(file.full_path)
                    if retval then
                        file_timestamps[file.full_path] = mtime
                    end
                end
            end
        end
        for _, file in ipairs(files) do
            if file.full_path then
                if old_metadata and old_metadata[file.full_path] then
                    file_metadata[file.full_path] = old_metadata[file.full_path]
                else
                    if not is_video_or_image_file(file.full_path) then
                        local meta = get_file_metadata(file.full_path)
                        file_metadata[file.full_path] = meta
                    end
                end
            end
        end
    end
    
    local data = {
        location = location,
        files = files,
        cache_time = os.time(),
        file_count = #files,
        file_timestamps = file_timestamps,
        file_metadata = file_metadata
    }
    local json_str = json.encode(data)
    local file = io.open(cache_file, "w")
    if file then
        file:write(json_str)
        file:close()
        return true
    end
    return false
end

local supported_extensions = {
    [".wav"] = true, [".mp3"] = true, [".mid"] = true, [".midi"] = true,
    [".aif"] = true, [".aiff"] = true, [".flac"] = true, [".ogg"] = true,
    [".wma"] = true, [".m4a"] = true, [".jpg"] = true, [".jpeg"] = true,
    [".png"] = true, [".gif"] = true, [".bmp"] = true, [".mp4"] = true,
    [".mov"] = true, [".avi"] = true, [".wmv"] = true, [".mkv"] = true
}

local tree_cache = {
    cache = {}  
}

local function get_cached_tree(path)
    local cached = tree_cache.cache[path]
    if cached then
        return cached
    end
    return nil
end

local function set_cached_tree(path, items)
    tree_cache.cache[path] = items
end

local function get_visible_column_count()
    local count = 0
    for _, visible in pairs(ui_settings.visible_columns) do
        if visible then count = count + 1 end
    end
    return count
end

local function get_column_name_by_index(visible_index)
    local column_order = {
        "name", "type", "size", "duration", "sample_rate", "channels", "bpm", "key",
        "artist", "album", "title", "track", "year", "genre", "comment",
        "composer", "publisher", "timesignature", "bitrate", "bitspersample",
        "encoder", "copyright", "desc", "originator", "originatorref",
        "date", "time", "umid"
    }
    
    local current_index = 0
    for _, col_name in ipairs(column_order) do
        if ui_settings.visible_columns[col_name] then
            if current_index == visible_index then
                return col_name
            end
            current_index = current_index + 1
        end
    end
    return nil
end

local function change_location(new_location)
    if file_location.current_location ~= new_location then
        file_location.current_location = new_location
        clear_sort_cache()
    end
end

local function has_supported_extension(filename)
    local ext = string.lower(string.match(filename, "%.([^%.]+)$") or "")
    if ext and ext ~= "" then
        return supported_extensions["." .. ext] or false
    end
    return false
end

local function build_flat_file_list(root_path)
    local result = {}
    local file_count = 0
    local max_files = 100000
    local dir_queue = {}
    table.insert(dir_queue, {path = root_path, relative = ""})
    while #dir_queue > 0 and file_count < max_files do
        local current = table.remove(dir_queue, 1)
        local dir_path = current.path
        local relative_path = current.relative
        local i = 0
        while file_count < max_files do
            local file = r.EnumerateFiles(dir_path, i)
            if not file then break end
            if has_supported_extension(file) then
                local parent_folder = relative_path:match("([^/\\]+)$") or ""
                local full_path
                if dir_path:sub(-1) == sep then
                    full_path = dir_path .. file
                else
                    full_path = dir_path .. sep .. file
                end
                
                local is_video_or_image = is_video_or_image_file(file)
                
                local is_valid = true
                if not is_video_or_image then
                    local source = r.PCM_Source_CreateFromFile(full_path)
                    if source then
                        local sample_rate = r.GetMediaSourceSampleRate(source)
                        r.PCM_Source_Destroy(source)
                        if sample_rate == 0 then
                            is_valid = false
                        end
                    end
                end
                
                if is_valid then
                    local ext = string.lower(string.match(file, "%.([^%.]+)$") or "")
                    table.insert(result, {
                        name = file,
                        is_dir = false,
                        full_path = full_path,
                        parent_folder = parent_folder,
                        ext = ext,
                        name_lower = string.lower(file)
                    })
                    file_count = file_count + 1
                end
            end
            i = i + 1
        end
        local j = 0
        while true do
            local subdir = r.EnumerateSubdirectories(dir_path, j)
            if not subdir then break end
            local new_path = dir_path .. sep .. subdir
            local new_relative = relative_path ~= "" and (relative_path .. sep .. subdir) or subdir
            table.insert(dir_queue, {path = new_path, relative = new_relative})
            j = j + 1
        end
    end
    table.sort(result, function(a, b)
        return a.name:lower() < b.name:lower()
    end)
    return result, file_count
end

local function load_file_cache(location)
    local cache_file = cache_dir .. "file_cache_" .. location:gsub("[^%w]", "_") .. ".json"
    local file = io.open(cache_file, "r")
    if file then
        local json_str = file:read("*all")
        file:close()
        local data = json.decode(json_str)
        if data and data.location == location and data.files then
            return data.files, data.file_timestamps or {}, data.cache_time or 0, data.file_metadata or {}
        end
    end
    return nil, {}, 0, {}
end

local function incremental_update_cache(location)
    local cached_files, cached_timestamps, cache_time, cached_metadata_table = load_file_cache(location)
    if not cached_files then
        cache_mgmt.scan_message = "Full scan..."
        return nil
    end
    
    local has_js_api = reaper.JS_Dialog_BrowseForSaveFile ~= nil
    if not has_js_api then
        cache_mgmt.scan_message = "Full scan (JS API not available)..."
        return nil
    end
    
    local existing_files = {}
    for _, file in ipairs(cached_files) do
        existing_files[file.full_path] = file
    end
    
    local updated_files = {}
    local changes_found = false
    local new_count = 0
    local modified_count = 0
    local removed_count = 0
    
    local function scan_directory(dir_path, relative_path)
        local i = 0
        while true do
            local filename = r.EnumerateFiles(dir_path, i)
            if not filename then break end
            
            if has_supported_extension(filename) then
                local full_path
                if dir_path:sub(-1) == sep then
                    full_path = dir_path .. filename
                else
                    full_path = dir_path .. sep .. filename
                end
                
                local cached_file = existing_files[full_path]
                if cached_file then
                    local retval, size, mtime = reaper.JS_File_Stat(full_path)
                    if retval and cached_timestamps[full_path] then
                        local current_mtime = tonumber(mtime) or 0
                        local cached_mtime = tonumber(cached_timestamps[full_path]) or 0
                        
                        if (current_mtime - cached_mtime) > 1 then
                            local is_video_or_image = is_video_or_image_file(filename)
                            
                            local is_valid = true
                            if not is_video_or_image then
                                local source = r.PCM_Source_CreateFromFile(full_path)
                                if source then
                                    local sample_rate = r.GetMediaSourceSampleRate(source)
                                    r.PCM_Source_Destroy(source)
                                    if sample_rate == 0 then
                                        is_valid = false
                                    end
                                end
                            end
                            
                            if is_valid then
                                table.insert(updated_files, cached_file)
                                modified_count = modified_count + 1
                                changes_found = true
                                cached_timestamps[full_path] = nil
                                if is_video_or_image then
                                    cached_metadata_table[full_path] = nil
                                else
                                    cached_metadata_table[full_path] = get_file_metadata(full_path)
                                end
                            else
                                removed_count = removed_count + 1
                                changes_found = true
                                cached_metadata_table[full_path] = nil
                            end
                        else
                            table.insert(updated_files, cached_file)
                        end
                    else
                        table.insert(updated_files, cached_file)
                    end
                    existing_files[full_path] = nil
                else
                    local parent_folder = relative_path:match("([^/\\]+)$") or ""
                    local is_video_or_image = is_video_or_image_file(filename)
                    
                    local is_valid = true
                    if not is_video_or_image then
                        local source = r.PCM_Source_CreateFromFile(full_path)
                        if source then
                            local sample_rate = r.GetMediaSourceSampleRate(source)
                            r.PCM_Source_Destroy(source)
                            if sample_rate == 0 then
                                is_valid = false
                            end
                        end
                    end
                    
                    if is_valid then
                        local ext = string.lower(string.match(filename, "%.([^%.]+)$") or "")
                        table.insert(updated_files, {
                            name = filename,
                            is_dir = false,
                            full_path = full_path,
                            parent_folder = parent_folder,
                            ext = ext,
                            name_lower = string.lower(filename)
                        })
                        new_count = new_count + 1
                        changes_found = true
                        if not is_video_or_image then
                            cached_metadata_table[full_path] = get_file_metadata(full_path)
                        else
                            cached_metadata_table[full_path] = nil
                        end
                    end
                end
            end
            i = i + 1
        end
        
        local j = 0
        while true do
            local subdir = r.EnumerateSubdirectories(dir_path, j)
            if not subdir then break end
            local new_path = dir_path .. sep .. subdir
            local new_relative = relative_path ~= "" and (relative_path .. sep .. subdir) or subdir
            scan_directory(new_path, new_relative)
            j = j + 1
        end
    end
    
    scan_directory(location, "")
    
    for path, _ in pairs(existing_files) do
        removed_count = removed_count + 1
        changes_found = true
        cached_metadata_table[path] = nil
    end
    
    if not changes_found then
        cache_mgmt.scan_message = "No changes - cache up-to-date"
        cache_mgmt.message_timer = os.time()
        return cached_files
    end
    
    table.sort(updated_files, function(a, b)
        return a.name:lower() < b.name:lower()
    end)
    
    local status_parts = {}
    if new_count > 0 then
        table.insert(status_parts, string.format("+%d new", new_count))
    end
    if modified_count > 0 then
        table.insert(status_parts, string.format("~%d modified", modified_count))
    end
    if removed_count > 0 then
        table.insert(status_parts, string.format("-%d removed", removed_count))
    end
    
    cache_mgmt.scan_message = table.concat(status_parts, ", ")
    cache_mgmt.message_timer = os.time()
    
    save_file_cache_with_timestamps(location, updated_files, cached_timestamps, cached_metadata_table)
    
    return updated_files
end

local function refresh_file_cache(location)
    local cache_file = cache_dir .. "file_cache_" .. location:gsub("[^%w]", "_") .. ".json"
    
    if cache_mgmt.loading_files then
        return
    end
    
    cache_mgmt.scan_message = "Scanning for changes..."
    cache_mgmt.message_timer = os.time()
    
    local updated_files = incremental_update_cache(location)
    
    if updated_files then
        search_filter.cached_flat_files = updated_files
        search_filter.cached_location = location
        search_filter.filtered_files = updated_files
    else
        os.remove(cache_file)
        search_filter.cached_location = ""
        search_filter.cached_flat_files = {}
        cache_mgmt.loading_files = true
        cache_mgmt.show_progress = true
        cache_mgmt.processed_files = 0
        cache_mgmt.total_files = 0
        cached_metadata = {}
        
        cache_mgmt.scan_message = "Counting files..."
        cache_mgmt.message_timer = os.time()
        
        r.defer(function()
            local scan_state = {
                dir_queue = {{path = location, relative = ""}},
                files = {},
                file_count = 0,
                phase = "counting"
            }
            
            local function process_batch()
                local batch_size = 50
                local processed = 0
                
                if scan_state.phase == "counting" then
                    while processed < batch_size and #scan_state.dir_queue > 0 do
                        local current = table.remove(scan_state.dir_queue, 1)
                        local dir_path = current.path
                        local relative_path = current.relative
                        
                        local i = 0
                        while true do
                            local filename = r.EnumerateFiles(dir_path, i)
                            if not filename then break end
                            
                            if has_supported_extension(filename) then
                                local parent_folder = relative_path:match("([^/\\]+)$") or ""
                                local full_path
                                if dir_path:sub(-1) == sep then
                                    full_path = dir_path .. filename
                                else
                                    full_path = dir_path .. sep .. filename
                                end
                                
                                local ext = string.lower(string.match(filename, "%.([^%.]+)$") or "")
                                
                                local is_valid = true
                                if ext == "mid" or ext == "midi" then
                                    local source = r.PCM_Source_CreateFromFile(full_path)
                                    if source then
                                        local length = r.GetMediaSourceLength(source)
                                        r.PCM_Source_Destroy(source)
                                        if not length or length <= 0 then
                                            is_valid = false
                                        end
                                    else
                                        is_valid = false
                                    end
                                elseif not is_video_or_image_file(full_path) then
                                    local source = r.PCM_Source_CreateFromFile(full_path)
                                    if source then
                                        local sample_rate = r.GetMediaSourceSampleRate(source)
                                        r.PCM_Source_Destroy(source)
                                        if not sample_rate or sample_rate == 0 then
                                            is_valid = false
                                        end
                                    else
                                        is_valid = false
                                    end
                                end
                                
                                if is_valid then
                                    table.insert(scan_state.files, {
                                        name = filename,
                                        is_dir = false,
                                        full_path = full_path,
                                        parent_folder = parent_folder,
                                        ext = ext,
                                        name_lower = string.lower(filename)
                                    })
                                    scan_state.file_count = scan_state.file_count + 1
                                end
                            end
                            i = i + 1
                            processed = processed + 1
                        end
                        
                        local j = 0
                        while true do
                            local subdir = r.EnumerateSubdirectories(dir_path, j)
                            if not subdir then break end
                            local new_path = dir_path .. sep .. subdir
                            local new_relative = relative_path ~= "" and (relative_path .. sep .. subdir) or subdir
                            table.insert(scan_state.dir_queue, {path = new_path, relative = new_relative})
                            j = j + 1
                        end
                    end
                    
                    cache_mgmt.scan_message = string.format("Found %d files...", scan_state.file_count)
                    
                    if #scan_state.dir_queue == 0 then
                        table.sort(scan_state.files, function(a, b)
                            return a.name:lower() < b.name:lower()
                        end)
                        
                        local non_video_count = 0
                        for _, file in ipairs(scan_state.files) do
                            if file.full_path and not is_video_or_image_file(file.full_path) then
                                non_video_count = non_video_count + 1
                            end
                        end
                        cache_mgmt.total_files = non_video_count
                        cache_mgmt.processed_files = 0
                        scan_state.phase = "metadata"
                        scan_state.current_index = 1
                    end
                    
                    r.defer(process_batch)
                elseif scan_state.phase == "metadata" then
                    save_file_cache_progressive(location, scan_state.files, scan_state.current_index)
                end
            end
            
            process_batch()
        end)
    end
end

local function clear_all_cache_files()
    local deleted_count = 0
    local i = 0
    
    while true do
        local file = r.EnumerateFiles(cache_dir, i)
        if not file then break end
        
        if file:match("%.json$") then
            local file_path = cache_dir .. file
            local success = os.remove(file_path)
            if success then
                deleted_count = deleted_count + 1
            end
        end
        i = i + 1
    end
    
    search_filter.cached_location = ""
    search_filter.cached_flat_files = {}
    tree_cache.cache = {}
    
    cache_mgmt.scan_message = string.format("Cleared %d cache file(s)", deleted_count)
    cache_mgmt.message_timer = os.time()
    
    return deleted_count
end

local function load_collections()
    file_location.collections = {}
    local i = 0
    repeat
        local file = reaper.EnumerateFiles(collections_dir, i)
        if file and file:match("%.json$") then
            local db_name = file:gsub("%.json$", "")
            table.insert(file_location.collections, db_name)
        end
        i = i + 1
    until not file
    return file_location.collections
end

local function save_collection(db_name, data)
    local db_file = collections_dir .. db_name .. ".json"
    local file = io.open(db_file, "w")
    if file then
        file:write(json.encode(data))
        file:close()
        return true
    end
    return false
end

local function load_collection(db_name)
    local db_file = collections_dir .. db_name .. ".json"
    local file = io.open(db_file, "r")
    if file then
        local content = file:read("*all")
        file:close()
        local data = json.decode(content)
        return data
    end
    return nil
end

local function create_new_collection(db_name)
    local data = {
        name = db_name,
        created = os.date("%Y-%m-%d %H:%M:%S"),
        categories = {},
        items = {}
    }
    return save_collection(db_name, data)
end

local function add_category_to_collection(db_name, category_name)
    local db = load_collection(db_name)
    if db then
        db.categories = db.categories or {}
        for _, cat in ipairs(db.categories) do
            if cat == category_name then
                return false
            end
        end
        table.insert(db.categories, category_name)
        return save_collection(db_name, db)
    end
    return false
end

local function remove_category_from_collection(db_name, category_name)
    local db = load_collection(db_name)
    if db then
        for i, cat in ipairs(db.categories or {}) do
            if cat == category_name then
                table.remove(db.categories, i)
                break
            end
        end
        for _, item in ipairs(db.items) do
            if item.categories then
                for i = #item.categories, 1, -1 do
                    if item.categories[i] == category_name then
                        table.remove(item.categories, i)
                    end
                end
            end
        end
        return save_collection(db_name, db)
    end
    return false
end

local function get_collection_items_by_category(db_name, category_filter)
    local db = load_collection(db_name)
    if not db then return {} end
    
    if not category_filter or category_filter == "" or category_filter == "All" then
        return db.items
    end
    
    local filtered = {}
    for _, item in ipairs(db.items) do
        if item.categories then
            for _, cat in ipairs(item.categories) do
                if cat == category_filter then
                    table.insert(filtered, item)
                    break
                end
            end
        end
    end
    return filtered
end

local function delete_collection(db_name)
    local db_file = collections_dir .. db_name .. ".json"
    return os.remove(db_file)
end

local function rename_collection(old_name, new_name)
    for _, db in ipairs(file_location.collections) do
        if db == new_name then
            return false, "Collection with this name already exists"
        end
    end
    
    if new_name:match('[<>:"/\\|?*]') then
        return false, "Collection name contains invalid characters"
    end
    
    local old_file = collections_dir .. old_name .. ".json"
    local new_file = collections_dir .. new_name .. ".json"
    
    local db_data = load_collection(old_name)
    if not db_data then
        return false, "Could not load collection"
    end
    
    db_data.name = new_name
    
    if not save_collection(new_name, db_data) then
        return false, "Could not save collection with new name"
    end
    
    if not os.remove(old_file) then
        os.remove(new_file)
        return false, "Could not remove old collection file"
    end
    
    if file_location.selected_collection == old_name then
        file_location.selected_collection = new_name
    end
    if file_location.last_collection_name == old_name then
        file_location.last_collection_name = new_name
    end
    
    load_collections()
    
    if file_location.selected_collection == new_name then
        local items = get_collection_items_by_category(new_name, file_location.selected_category)
        file_location.current_files = {}
        search_filter.cached_flat_files = {}
        for _, item in ipairs(items) do
            local file_entry = {
                name = item.path:match("([^/\\]+)$"),
                full_path = item.path,
                is_dir = false
            }
            table.insert(file_location.current_files, file_entry)
            table.insert(search_filter.cached_flat_files, file_entry)
        end
        file_location.current_location = "Collection: " .. new_name
        search_filter.cached_location = file_location.current_location
        search_filter.filtered_files = search_filter.cached_flat_files
    end
    
    return true, "Collection renamed successfully"
end

local function add_file_to_collection(db_name, file_path, categories)
    local db = load_collection(db_name)
    if db then
        for _, item in ipairs(db.items) do
            if item.path == file_path then
                if categories and #categories > 0 then
                    item.categories = categories
                    return save_collection(db_name, db)
                end
                return true
            end
        end
        
        local new_item = {
            path = file_path,
            added = os.date("%Y-%m-%d %H:%M:%S")
        }
        if categories and #categories > 0 then
            new_item.categories = categories
        end
        table.insert(db.items, new_item)
        return save_collection(db_name, db)
    end
    return false
end

local function remove_file_from_collection(db_name, index)
    local db = load_collection(db_name)
    if db and db.items[index] then
        table.remove(db.items, index)
        return save_collection(db_name, db)
    end
    return false
end

local function is_file_selected(file_path)
    for _, selected_path in ipairs(file_location.selected_files) do
        if selected_path == file_path then
            return true
        end
    end
    return false
end

local function toggle_file_selection(file_path)
    for i, selected_path in ipairs(file_location.selected_files) do
        if selected_path == file_path then
            table.remove(file_location.selected_files, i)
            return
        end
    end
    table.insert(file_location.selected_files, file_path)
end

local function clear_file_selection()
    file_location.selected_files = {}
    file_location.last_selected_index = nil
end

local function select_file_range(start_index, end_index, files_list)
    if start_index > end_index then
        start_index, end_index = end_index, start_index
    end
    
    for i = start_index, end_index do
        if files_list[i] and not files_list[i].is_dir then
            local file_path = files_list[i].full_path
            if not is_file_selected(file_path) then
                table.insert(file_location.selected_files, file_path)
            end
        end
    end
end

local function add_multiple_files_to_collection(db_name, file_paths, categories)
    local db = load_collection(db_name)
    if db then
        local added_count = 0
        for _, file_path in ipairs(file_paths) do
            local already_exists = false
            for _, item in ipairs(db.items) do
                if item.path == file_path then
                    already_exists = true
                    if categories and #categories > 0 then
                        item.categories = categories
                    end
                    break
                end
            end
            
            if not already_exists then
                local new_item = {
                    path = file_path,
                    added = os.date("%Y-%m-%d %H:%M:%S")
                }
                if categories and #categories > 0 then
                    new_item.categories = categories
                end
                table.insert(db.items, new_item)
                added_count = added_count + 1
            end
        end
        
        if added_count > 0 or (categories and #categories > 0) then
            save_collection(db_name, db)
        end
        return added_count
    end
    return 0
end
local function read_directory_recursive(root_path)
    local cached, timestamps, cache_time = load_file_cache(root_path)
    if cached then
        return cached
    end
    local files = build_flat_file_list(root_path)
    save_file_cache(root_path, files)
    return files
end
local function apply_style()
end
local function update_monitor_positions()
    if waveform.normalized_sel_start >= 0 and waveform.normalized_sel_end > waveform.normalized_sel_start and waveform.monitor_file_path ~= "" then
        local source = r.PCM_Source_CreateFromFile(waveform.monitor_file_path)
        if source then
            local file_length = r.GetMediaSourceLength(source)
            r.PCM_Source_Destroy(source)
            if file_length and file_length > 0 then
                waveform.monitor_sel_start = waveform.normalized_sel_start * file_length / (playback.effective_playrate or 1.0)
                waveform.monitor_sel_end = waveform.normalized_sel_end * file_length / (playback.effective_playrate or 1.0)
            end
        end
    end
end
local function remove_style()
end
local function button_is_active(state_value)
    return state_value == true
end
local function draw_styled_button(label, width, is_active, callback)
    local result = false
    if is_active then
        result = reaper.ImGui_Button(ctx, label, width)
    else
        result = reaper.ImGui_Button(ctx, label, width)
    end
    if result then
        if callback then
            callback()
        end
    end
    return result
end
local function serialize(val, name, skipnewlines, depth)
    skipnewlines = skipnewlines or false
    depth = depth or 0
    local indent = string.rep(" ", depth)
    local function format_key(k)
        local t = type(k)
        if t == "number" then
            return "[" .. tostring(k) .. "]"
        elseif t == "string" then
            if k:match("^[_%a][_%w]*$") then
                return k
            else
                return "[" .. string.format("%q", k) .. "]"
            end
        else
            return "[" .. string.format("%q", tostring(k)) .. "]"
        end
    end
    local out = indent
    if name ~= nil then
        out = out .. format_key(name) .. " = "
    end
    local tv = type(val)
    if tv == "table" then
        out = out .. "{" .. (not skipnewlines and "\n" or "")
        for k, v in pairs(val) do
            out = out .. serialize(v, k, skipnewlines, depth + 1) .. "," .. (not skipnewlines and "\n" or "")
        end
        out = out .. string.rep(" ", depth) .. "}"
    elseif tv == "number" then
        out = out .. tostring(val)
    elseif tv == "string" then
        out = out .. string.format("%q", val)
    elseif tv == "boolean" then
        out = out .. (val and "true" or "false")
    else
        out = out .. string.format("%q", "[inserializeable datatype:" .. tv .. "]")
    end
    return out
end
local function LoadTexture(path)
    if texture_cache[path] then
        return texture_cache[path]
    end
    
    local ext = path:match("%.([^%.]+)$")
    if ext then ext = ext:lower() end
    
    local source_image = nil
    if ext == "png" then
        source_image = r.JS_LICE_LoadPNG(path)
    elseif ext == "jpg" or ext == "jpeg" then
        source_image = r.JS_LICE_LoadJPG(path)
    elseif ext == "bmp" then
        source_image = r.JS_LICE_LoadBMP(path)
    elseif ext == "gif" then
        return nil
    end
    
    if not source_image then return nil end
    
    local orig_width = r.JS_LICE_GetWidth(source_image)
    local orig_height = r.JS_LICE_GetHeight(source_image)
    
    local max_width = 800  
    local max_height = 120 
    
    local scale_x = max_width / orig_width
    local scale_y = max_height / orig_height
    local scale = math.min(scale_x, scale_y, 1.0)
    
    local target_width = math.floor(orig_width * scale)
    local target_height = math.floor(orig_height * scale)
    
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

local function LoadVideoThumbnail(path)
    if texture_cache[path] then
        return texture_cache[path]
    end
    
    return nil
end

local function save_browser_position()
    local value = ui_settings.browser_position_left and "left" or "right"
    r.SetExtState("TK_MEDIA_BROWSER", "browser_position", value, true)
end
local function load_browser_position()
    local value = r.GetExtState("TK_MEDIA_BROWSER", "browser_position")
    if value ~= "" then
        ui_settings.browser_position_left = (value == "left")
    end
end
local function save_options()
    local file = io.open(r.GetResourcePath() .. "/Scripts/TK_media_browser_options.txt", "w")
    if file then
        local options = {
            auto_play = playback.auto_play,
            loop_play = playback.loop_play,
            use_original_speed = playback.use_original_speed,
            link_transport = playback.link_transport,
            link_start_from_editcursor = playback.link_start_from_editcursor,
            use_exclusive_solo = playback.use_exclusive_solo,
            preview_volume = playback.preview_volume,
            current_db = current_db,
            remember_last_location = file_location.remember_last_location,
            last_location_index = file_location.selected_location_index,
            show_oscilloscope = ui.show_oscilloscope,
            waveform_grid_overlay = ui.waveform_grid_overlay,
            show_collection_section = ui.show_collection_section,
            current_view_mode = ui.current_view_mode,
            selected_collection = file_location.selected_collection,
            last_folder_location = file_location.last_folder_location,
            last_folder_index = file_location.last_folder_index,
            last_collection_name = file_location.last_collection_name,
            flat_view = file_location.flat_view,
            remember_window_position = ui.remember_window_position,
            window_x = ui.window_x,
            window_y = ui.window_y,
            file_browser_open = ui_settings.file_browser_open,
            browser_position_left = ui_settings.browser_position_left,
            window_bg_brightness = ui_settings.window_bg_brightness,
            window_opacity = ui_settings.window_opacity,
            text_brightness = ui_settings.text_brightness,
            grid_brightness = ui_settings.grid_brightness,
            button_brightness = ui_settings.button_brightness,
            button_text_brightness = ui_settings.button_text_brightness,
            waveform_hue = ui_settings.waveform_hue,
            waveform_thickness = ui_settings.waveform_thickness,
            waveform_resolution_multiplier = ui_settings.waveform_resolution_multiplier,
            accent_hue = ui_settings.accent_hue,
            selection_hue = ui_settings.selection_hue,
            selection_saturation = ui_settings.selection_saturation,
            show_waveform_bg = ui_settings.show_waveform_bg,
            hide_scrollbar = ui_settings.hide_scrollbar,
            selected_font = ui_settings.selected_font,
            button_height = ui_settings.button_height,
            use_numaplayer = ui_settings.use_numaplayer,
            numaplayer_preset = ui_settings.numaplayer_preset,
            use_selected_track_for_midi = ui_settings.use_selected_track_for_midi,
            pitch_detection_enabled = ui.pitch_detection_enabled,
            custom_folder_names = file_location.custom_folder_names,
            custom_folder_colors = file_location.custom_folder_colors,
            custom_collection_colors = file_location.custom_collection_colors,
            visible_columns = ui_settings.visible_columns,
            show_spectral_view = waveform.show_spectral_view
        }
        file:write(serialize(options))
        file:close()
    end
end

-- Preset management functions
local function get_settings_table()
    return {
        auto_play = playback.auto_play,
        loop_play = playback.loop_play,
        use_original_speed = playback.use_original_speed,
        link_transport = playback.link_transport,
        link_start_from_editcursor = playback.link_start_from_editcursor,
        use_exclusive_solo = playback.use_exclusive_solo,
        preview_volume = playback.preview_volume,
        show_oscilloscope = ui.show_oscilloscope,
        waveform_grid_overlay = ui.waveform_grid_overlay,
        flat_view = file_location.flat_view,
        file_browser_open = ui_settings.file_browser_open,
        browser_position_left = ui_settings.browser_position_left,
        window_bg_brightness = ui_settings.window_bg_brightness,
        window_opacity = ui_settings.window_opacity,
        text_brightness = ui_settings.text_brightness,
        grid_brightness = ui_settings.grid_brightness,
        button_brightness = ui_settings.button_brightness,
        button_text_brightness = ui_settings.button_text_brightness,
        waveform_hue = ui_settings.waveform_hue,
        waveform_thickness = ui_settings.waveform_thickness,
        waveform_resolution_multiplier = ui_settings.waveform_resolution_multiplier,
        accent_hue = ui_settings.accent_hue,
        selection_hue = ui_settings.selection_hue,
        selection_saturation = ui_settings.selection_saturation,
        show_waveform_bg = ui_settings.show_waveform_bg,
        hide_scrollbar = ui_settings.hide_scrollbar,
        selected_font = ui_settings.selected_font,
        button_height = ui_settings.button_height,
        visible_columns = ui_settings.visible_columns,
        show_spectral_view = waveform.show_spectral_view,
        pitch_detection_enabled = ui.pitch_detection_enabled
    }
end

local function apply_settings_from_table(settings)
    if not settings then return false end
    
    playback.auto_play = settings.auto_play
    playback.loop_play = settings.loop_play
    playback.use_original_speed = settings.use_original_speed
    playback.link_transport = settings.link_transport or false
    playback.link_start_from_editcursor = settings.link_start_from_editcursor or false
    playback.use_exclusive_solo = settings.use_exclusive_solo ~= nil and settings.use_exclusive_solo or true
    playback.preview_volume = settings.preview_volume
    ui.show_oscilloscope = settings.show_oscilloscope
    ui.waveform_grid_overlay = settings.waveform_grid_overlay or false
    waveform.show_spectral_view = settings.show_spectral_view or false
    file_location.flat_view = settings.flat_view ~= nil and settings.flat_view or false
    ui_settings.file_browser_open = settings.file_browser_open ~= nil and settings.file_browser_open or false
    ui_settings.browser_position_left = settings.browser_position_left ~= nil and settings.browser_position_left or true
    ui_settings.window_bg_brightness = settings.window_bg_brightness ~= nil and settings.window_bg_brightness or 0.12
    ui_settings.window_opacity = settings.window_opacity ~= nil and settings.window_opacity or 0.94
    ui_settings.text_brightness = settings.text_brightness ~= nil and settings.text_brightness or 1.0
    ui_settings.grid_brightness = settings.grid_brightness ~= nil and settings.grid_brightness or 1.0
    ui_settings.button_brightness = settings.button_brightness ~= nil and settings.button_brightness or 0.25
    ui_settings.button_text_brightness = settings.button_text_brightness ~= nil and settings.button_text_brightness or 1.0
    ui_settings.waveform_hue = settings.waveform_hue ~= nil and settings.waveform_hue or 0.55
    ui_settings.waveform_thickness = settings.waveform_thickness ~= nil and settings.waveform_thickness or 1.0
    ui_settings.waveform_resolution_multiplier = settings.waveform_resolution_multiplier ~= nil and settings.waveform_resolution_multiplier or 2.0
    ui_settings.accent_hue = settings.accent_hue ~= nil and settings.accent_hue or 0.55
    ui_settings.selection_hue = settings.selection_hue ~= nil and settings.selection_hue or 0.16
    ui_settings.selection_saturation = settings.selection_saturation ~= nil and settings.selection_saturation or 1.0
    ui_settings.show_waveform_bg = settings.show_waveform_bg ~= nil and settings.show_waveform_bg or false
    ui_settings.hide_scrollbar = settings.hide_scrollbar ~= nil and settings.hide_scrollbar or false
    ui_settings.selected_font = settings.selected_font or "Default"
    ui_settings.button_height = settings.button_height or 20
    ui_settings.visible_columns = settings.visible_columns or {name = true, size = true, date = true, duration = true, samplerate = true, bitdepth = true, channels = true}
    ui.pitch_detection_enabled = settings.pitch_detection_enabled ~= nil and settings.pitch_detection_enabled or true
    
    font_objects = {}
    update_fonts()
    
    save_options()
    return true
end

local function save_preset(preset_name)
    if not preset_name or preset_name == "" then return false end
    
    local settings = get_settings_table()
    local json_string = json.encode(settings)
    
    local file = io.open(presets_dir .. preset_name .. ".json", "w")
    if file then
        file:write(json_string)
        file:close()
        return true
    end
    return false
end

local function load_preset(preset_name)
    if not preset_name or preset_name == "" then return false, "No preset name provided" end
    
    local file = io.open(presets_dir .. preset_name .. ".json", "r")
    if not file then
        return false, "Preset file not found"
    end
    
    local content = file:read("*all")
    file:close()
    
    local success, settings = pcall(json.decode, content)
    if not success then
        return false, "Invalid JSON format in preset file"
    end
    
    if not settings or type(settings) ~= "table" then
        return false, "Corrupted preset data"
    end
    
    local apply_success = apply_settings_from_table(settings)
    if not apply_success then
        return false, "Failed to apply settings"
    end
    
    return true, "Success"
end

local function get_preset_list()
    local presets = {}
    local i = 0
    repeat
        local file = r.EnumerateFiles(presets_dir, i)
        if file and file:match("%.json$") then
            local name = file:gsub("%.json$", "")
            table.insert(presets, name)
        end
        i = i + 1
    until not file
    return presets
end

local function delete_preset(preset_name)
    if not preset_name or preset_name == "" then return false end
    os.remove(presets_dir .. preset_name .. ".json")
    return true
end

local function load_options()
    local file = io.open(r.GetResourcePath() .. "/Scripts/TK_media_browser_options.txt", "r")
    if file then
        local content = file:read("*all")
        file:close()
        local chunk, err = load("return " .. content)
        if chunk then
            local ok, options = pcall(chunk)
            if not ok then options = nil end
            ui.show_collection_section = options.show_collection_section or false
            ui.current_view_mode = options.current_view_mode or "folders"
            file_location.selected_collection = options.selected_collection
            file_location.last_folder_location = options.last_folder_location or ""
            file_location.last_folder_index = options.last_folder_index or 1
            file_location.last_collection_name = options.last_collection_name
            ui.show_oscilloscope = options.show_oscilloscope
            ui.waveform_grid_overlay = options.waveform_grid_overlay or false
            waveform.show_spectral_view = options.show_spectral_view or false
            if options.current_view_mode ~= "collections" then
                file_location.flat_view = options.flat_view ~= nil and options.flat_view or false
            end
            file_location.saved_folder_flat_view = options.flat_view ~= nil and options.flat_view or false
            playback.auto_play = options.auto_play
            playback.loop_play = options.loop_play
            playback.use_original_speed = options.use_original_speed
            playback.link_transport = options.link_transport or false
            playback.link_start_from_editcursor = options.link_start_from_editcursor or false
            playback.use_exclusive_solo = options.use_exclusive_solo ~= nil and options.use_exclusive_solo or true
            playback.preview_volume = options.preview_volume
            current_db = options.current_db
            file_location.remember_last_location = options.remember_last_location ~= nil and options.remember_last_location or true
            ui.remember_window_position = options.remember_window_position ~= nil and options.remember_window_position or true
            ui.window_x = options.window_x ~= nil and options.window_x or 100
            ui.window_y = options.window_y ~= nil and options.window_y or 100
            ui_settings.file_browser_open = options.file_browser_open ~= nil and options.file_browser_open or false
            ui_settings.browser_position_left = options.browser_position_left ~= nil and options.browser_position_left or true
            ui_settings.window_bg_brightness = options.window_bg_brightness ~= nil and options.window_bg_brightness or 0.12
            ui_settings.window_opacity = options.window_opacity ~= nil and options.window_opacity or 0.94
            ui_settings.text_brightness = options.text_brightness ~= nil and options.text_brightness or 1.0
            ui_settings.grid_brightness = options.grid_brightness ~= nil and options.grid_brightness or 1.0
            ui_settings.button_brightness = options.button_brightness ~= nil and options.button_brightness or 0.25
            ui_settings.button_text_brightness = options.button_text_brightness ~= nil and options.button_text_brightness or 1.0
            ui_settings.waveform_hue = options.waveform_hue ~= nil and options.waveform_hue or 0.55
            ui_settings.waveform_thickness = options.waveform_thickness ~= nil and options.waveform_thickness or 1.0
            ui_settings.waveform_resolution_multiplier = options.waveform_resolution_multiplier ~= nil and options.waveform_resolution_multiplier or 2.0
            ui_settings.accent_hue = options.accent_hue ~= nil and options.accent_hue or 0.55
            ui_settings.selection_hue = options.selection_hue ~= nil and options.selection_hue or 0.16
            ui_settings.selection_saturation = options.selection_saturation ~= nil and options.selection_saturation or 1.0
            if options.show_waveform_bg ~= nil then
                ui_settings.show_waveform_bg = options.show_waveform_bg
            else
                ui_settings.show_waveform_bg = true
            end
            if options.hide_scrollbar ~= nil then
                ui_settings.hide_scrollbar = options.hide_scrollbar
            else
                ui_settings.hide_scrollbar = false
            end
            ui_settings.selected_font = options.selected_font or "Arial"
            ui_settings.button_height = options.button_height or 25
            ui_settings.use_numaplayer = options.use_numaplayer or false
            ui_settings.numaplayer_preset = options.numaplayer_preset or ""
            ui_settings.use_selected_track_for_midi = options.use_selected_track_for_midi or false
            ui.pitch_detection_enabled = options.pitch_detection_enabled ~= nil and options.pitch_detection_enabled or true
            file_location.custom_folder_names = options.custom_folder_names or {}
            file_location.custom_folder_colors = options.custom_folder_colors or {}
            file_location.custom_collection_colors = options.custom_collection_colors or {}
            if options.visible_columns then
                ui_settings.visible_columns = options.visible_columns
            end
            if file_location.remember_last_location and options.last_location_index then
                file_location.selected_location_index = options.last_location_index
            end
        else
            save_options()
            local f2 = io.open(r.GetResourcePath() .. "/Scripts/TK_media_browser_options.txt", "r")
            if f2 then
                local content2 = f2:read("*all")
                f2:close()
                local chunk2 = load("return " .. content2)
                if chunk2 then
                    local ok2, options2 = pcall(chunk2)
                    if ok2 and options2 then
                        ui.show_collection_section = options2.show_collection_section or false
                        ui.current_view_mode = options2.current_view_mode or "folders"
                        file_location.selected_collection = options2.selected_collection
                        file_location.last_folder_location = options2.last_folder_location or ""
                        file_location.last_folder_index = options2.last_folder_index or 1
                        file_location.last_collection_name = options2.last_collection_name
                        ui.show_oscilloscope = options2.show_oscilloscope
                        ui.waveform_grid_overlay = options2.waveform_grid_overlay or false
                        if options2.current_view_mode ~= "collections" then
                            file_location.flat_view = options2.flat_view ~= nil and options2.flat_view or false
                        end
                        file_location.saved_folder_flat_view = options2.flat_view ~= nil and options2.flat_view or false
                        playback.auto_play = options2.auto_play
                        playback.loop_play = options2.loop_play
                        playback.use_original_speed = options2.use_original_speed
                        playback.link_transport = options2.link_transport or false
                        playback.preview_volume = options2.preview_volume
                        current_db = options2.current_db
                        file_location.remember_last_location = options2.remember_last_location ~= nil and options2.remember_last_location or true
                        ui.remember_window_position = options2.remember_window_position ~= nil and options2.remember_window_position or true
                        ui.window_x = options2.window_x ~= nil and options2.window_x or 100
                        ui.window_y = options2.window_y ~= nil and options2.window_y or 100
                        ui_settings.file_browser_open = options2.file_browser_open ~= nil and options2.file_browser_open or false
                        ui_settings.browser_position_left = options2.browser_position_left ~= nil and options2.browser_position_left or true
                        ui_settings.window_bg_brightness = options2.window_bg_brightness ~= nil and options2.window_bg_brightness or 0.12
                        ui_settings.window_opacity = options2.window_opacity ~= nil and options2.window_opacity or 0.94
                        ui_settings.text_brightness = options2.text_brightness ~= nil and options2.text_brightness or 1.0
                        ui_settings.grid_brightness = options2.grid_brightness ~= nil and options2.grid_brightness or 1.0
                        ui_settings.button_brightness = options2.button_brightness ~= nil and options2.button_brightness or 0.25
                        ui_settings.button_text_brightness = options2.button_text_brightness ~= nil and options2.button_text_brightness or 1.0
                        ui_settings.waveform_hue = options2.waveform_hue ~= nil and options2.waveform_hue or 0.55
                        ui_settings.waveform_thickness = options2.waveform_thickness ~= nil and options2.waveform_thickness or 1.0
                        ui_settings.accent_hue = options2.accent_hue ~= nil and options2.accent_hue or 0.55
                        if options2.show_waveform_bg ~= nil then
                            ui_settings.show_waveform_bg = options2.show_waveform_bg
                        else
                            ui_settings.show_waveform_bg = true
                        end
                        if options2.hide_scrollbar ~= nil then
                            ui_settings.hide_scrollbar = options2.hide_scrollbar
                        else
                            ui_settings.hide_scrollbar = false
                        end
                        ui_settings.selected_font = options2.selected_font or "Arial"
                        ui_settings.button_height = options2.button_height or 25
                        ui_settings.use_numaplayer = options2.use_numaplayer or false
                        ui.pitch_detection_enabled = options2.pitch_detection_enabled ~= nil and options2.pitch_detection_enabled or true
                        file_location.custom_folder_names = options2.custom_folder_names or {}
                        if file_location.remember_last_location and options2.last_location_index then
                            file_location.selected_location_index = options2.last_location_index
                        end
                    end
                end
            end
        end
    end
end
local function save_search_history()
    for i, term in ipairs(search_filter.search_history) do
        r.SetExtState("TK_MEDIA_BROWSER", "search_history_" .. i, term, true)
    end
    r.SetExtState("TK_MEDIA_BROWSER", "search_history_count", tostring(#search_filter.search_history), true)
end
local function load_search_history()
    local count = tonumber(r.GetExtState("TK_MEDIA_BROWSER", "search_history_count")) or 0
    search_filter.search_history = {}
    for i = 1, math.min(count, search_filter.max_search_history) do
        local term = r.GetExtState("TK_MEDIA_BROWSER", "search_history_" .. i)
        if term and term ~= "" then
            table.insert(search_filter.search_history, term)
        end
    end
end
local function add_to_search_history(term)
    if term == "" then return end
    for i = #search_filter.search_history, 1, -1 do
        if search_filter.search_history[i] == term then
            table.remove(search_filter.search_history, i)
        end
    end
    table.insert(search_filter.search_history, 1, term)
    while #search_filter.search_history > search_filter.max_search_history do
        table.remove(search_filter.search_history)
    end
    save_search_history()
end
load_options()
load_search_history()

update_fonts()
playback.pending_sync_refresh = true

local function linear_to_db(linear)
    return 20 * math.log(linear, 10)
end
local function db_to_linear(db)
    return 10 ^ (db / 20)
end
local function generate_peak_file(file_path)
    local file_name = file_path:match("([^/\\]+)$")
    local peak_file_path = peakfiles_path .. file_name .. ".peak"
    local source = r.PCM_Source_CreateFromFile(file_path)
    if source then
        r.PCM_Source_BuildPeaks(source, 0)
        r.PCM_Source_BuildPeaks(source, 1)
        r.PreventUIRefresh(1)
        r.UpdateTimeline()
        r.Main_OnCommand(40047, 0)
        r.PreventUIRefresh(0)
        r.PCM_Source_Destroy(source)
    end
end

local function calculate_spectral_data(file_path, num_slices, num_freq_bands)
    local spectral_data = {}
    
    local temp_track = r.GetTrack(0, 0)
    if not temp_track then 
        return spectral_data 
    end
    
    local temp_item = r.AddMediaItemToTrack(temp_track)
    if not temp_item then return spectral_data end
    
    local take = r.AddTakeToMediaItem(temp_item)
    if not take then
        r.DeleteTrackMediaItem(temp_track, temp_item)
        return spectral_data
    end
    
    local source = r.PCM_Source_CreateFromFile(file_path)
    if not source then
        r.DeleteTrackMediaItem(temp_track, temp_item)
        return spectral_data
    end
    
    r.SetMediaItemTake_Source(take, source)
    local length = r.GetMediaSourceLength(source)
    
    if not length or length <= 0 then
        r.DeleteTrackMediaItem(temp_track, temp_item)
        return spectral_data
    end
    
    r.SetMediaItemLength(temp_item, length, false)
    r.UpdateItemInProject(temp_item)
    
    local accessor = r.CreateTakeAudioAccessor(take)
    if accessor then
        local samplerate = r.GetMediaSourceSampleRate(source) or 44100
        local numch = 1 -- Use mono for spectral analysis
        local fft_size = 1024
        
        local split1 = 0.16  -- Bass (kick drum range)
        local split2 = 0.32  -- Low-mid (snare fundamental)
        local split3 = 0.50  -- Mid (toms/vocals)
        local split4 = 0.70  -- High-mid
        local split5 = 0.85  -- High (cymbals/hats)
        
        for slice = 0, num_slices - 1 do
            local start_time = (slice / num_slices) * length
            local samplebuffer = r.new_array(fft_size * 2)
            
            local ok = r.GetAudioAccessorSamples(accessor, samplerate, numch, start_time, fft_size, samplebuffer)
            
            if ok > 0 then
                samplebuffer.fft_real(fft_size, true)
                
                local bands = {0, 0, 0, 0, 0, 0}
                local band_counts = {0, 0, 0, 0, 0, 0}
                
                for bin = 1, fft_size / 2 - 1 do
                    local Re = samplebuffer[bin * 2]
                    local Im = samplebuffer[bin * 2 + 1]
                    local magnitude = math.sqrt(Re * Re + Im * Im)
                    
                    local ratio = bin / (fft_size / 2)
                    local band_idx
                    if ratio < split1 then
                        band_idx = 1
                    elseif ratio < split2 then
                        band_idx = 2
                    elseif ratio < split3 then
                        band_idx = 3
                    elseif ratio < split4 then
                        band_idx = 4
                    elseif ratio < split5 then
                        band_idx = 5
                    else
                        band_idx = 6
                    end
                    
                    bands[band_idx] = bands[band_idx] + magnitude
                    band_counts[band_idx] = band_counts[band_idx] + 1
                end
                
                for b = 1, 6 do
                    if band_counts[b] > 0 then
                        bands[b] = bands[b] / band_counts[b]
                    end
                end
                
                bands[1] = bands[1] * 0.15  -- Bass - reduce slightly more
                bands[2] = bands[2] * 0.20  -- Low-mid
                bands[3] = bands[3] * 0.35  -- Mid
                bands[4] = bands[4] * 0.70  -- High-mid
                bands[5] = bands[5] * 1.30  -- High - boost more
                bands[6] = bands[6] * 2.20  -- Highest - boost more
                
                local total = 0
                for b = 1, 6 do
                    total = total + bands[b]
                end
                if total > 0 then
                    for b = 1, 6 do
                        bands[b] = bands[b] / total
                    end
                end
                
                for b = 1, 6 do
                    bands[b] = bands[b] * bands[b]  -- ^2
                end
                
                total = 0
                for b = 1, 6 do
                    total = total + bands[b]
                end
                if total > 0 then
                    for b = 1, 6 do
                        bands[b] = bands[b] / total
                    end
                end
                
                local weighted_sum = 0
                for b = 1, 6 do
                    weighted_sum = weighted_sum + (bands[b] * (b - 1))
                end
                
                local spectral_value = weighted_sum / 5.0
                
                spectral_value = spectral_value ^ 0.7
                
                table.insert(spectral_data, spectral_value)
            else
                table.insert(spectral_data, 0.5) 
            end
            
            samplebuffer.clear()
        end
        r.DestroyAudioAccessor(accessor)
    end
    
    r.DeleteTrackMediaItem(temp_track, temp_item)
    
    return spectral_data
end 

local function is_video_window_open()
    local video_window_state = r.GetToggleCommandStateEx(0, 50125)
    return video_window_state == 1
end
local function restore_focus_to_browser()
    r.ImGui_SetNextWindowFocus(ctx)
end
local function force_peaks_in_item(item, take)
    if not item or not take then return end
    r.UpdateItemInProject(item)
    local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
    r.SetMediaItemInfo_Value(item, "D_POSITION", pos + 0.0001)
    r.UpdateItemInProject(item)
    r.SetMediaItemInfo_Value(item, "D_POSITION", pos)
    r.UpdateItemInProject(item)
    r.MarkProjectDirty(0)
    r.UpdateArrange()
end

local function safe_delete_media_item(track, item)
    if not track or not item then return false end
    
    local item_count = r.CountTrackMediaItems(track)
    for i = 0, item_count - 1 do
        if r.GetTrackMediaItem(track, i) == item then
            r.DeleteTrackMediaItem(track, item)
            return true
        end
    end
    
    return false 
end

local function on_exit()
    save_options()
    
    if playback.link_transport then
        r.Main_OnCommand(1016, 0)
    end
    
    local was_track_playback = playback.is_video_playback or playback.is_midi_playback
    
    if playback.is_video_playback or playback.is_midi_playback then
        r.Main_OnCommand(1016, 0)  
        if playback.video_preview_item and playback.video_preview_track then
            safe_delete_media_item(playback.video_preview_track, playback.video_preview_item)
            if playback.is_video_playback then
                r.DeleteTrack(playback.video_preview_track)
                playback.video_preview_track = nil
            else
                r.SetMediaTrackInfo_Value(playback.video_preview_track, "I_SOLO", 0)
            end
            
            for track_idx, solo_state in pairs(playback.saved_solo_states) do
                local track = r.GetTrack(0, track_idx)
                if track then
                    r.SetMediaTrackInfo_Value(track, "I_SOLO", solo_state)
                end
            end
            playback.saved_solo_states = {} 
            playback.saved_solo_states = {}
        end
        playback.video_preview_item = nil
        playback.is_video_playback = false
        playback.is_midi_playback = false
        playback.playing_source = nil
    end
    
    if playback.playing_preview then
        r.CF_Preview_Stop(playback.playing_preview)
        playback.playing_preview = nil
    end
    r.CF_Preview_StopAll()
    
    if playback.playing_source and not was_track_playback then
        r.PCM_Source_Destroy(playback.playing_source)
        playback.playing_source = nil
    elseif was_video_playback then
        playback.playing_source = nil
    end
    playback.playing_path = nil
    
    r.PreventUIRefresh(1) 
    r.Undo_BeginBlock()
    
    local track_count = r.CountTracks(0)
    for i = track_count - 1, 0, -1 do  
        local track = r.GetTrack(0, i)
        if track then
            local _, name = r.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
            if name == "__VIDEO_PREVIEW__" or name == "__MEDIA_PREVIEW__" then
                local item_count = r.CountTrackMediaItems(track)
                for j = item_count - 1, 0, -1 do
                    local item = r.GetTrackMediaItem(track, j)
                    r.DeleteTrackMediaItem(track, item)
                end
                r.DeleteTrack(track)
                break
            end
        end
    end
    
    r.Undo_EndBlock("TK Media Browser Cleanup", -1)
    r.PreventUIRefresh(-1)  
    r.UpdateArrange()
end
local function check_numa_player_installed()
    local track = r.GetTrack(0, 0)
    if track then
        local fx_index = r.TrackFX_AddByName(track, "Numa Player (Studiologic)", false, -1)
        if fx_index ~= -1 then
            r.TrackFX_Delete(track, fx_index)
            plugin_state.numa_player_installed = true
        else
            plugin_state.numa_player_installed = false
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
        for _, location in ipairs(file_location.locations) do
            file:write(location .. "\n")
        end
        file:close()
    end
end
local function load_locations()
    local file = io.open(r.GetResourcePath() .. "/Scripts/TK_media_browser_locations.txt", "r")
    if file then
        for line in file:lines() do
            table.insert(file_location.locations, line)
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
local function build_visible_files_list(items, path, result)
    result = result or {}
    for _, item in ipairs(items) do
        if not item.is_dir then
            local full_path
            if path:sub(-1) == sep then
                full_path = path .. item.name
            else
                full_path = path .. sep .. item.name
            end
            table.insert(result, {
                name = item.name,
                path = full_path,
                full_path = full_path,
                parent_folder = path:match("([^/\\]+)$") or ""
            })
        else
            if item.items then
                build_visible_files_list(item.items, path .. sep .. item.name, result)
            end
        end
    end
    return result
end
local function get_audio_data()
    if not playback.playing_preview then
        ui_settings.audio_buffer = {}
        waveform.current_pitch_note = "No preview"
        return
    end
    local current_time = r.time_precise()
    if current_time - ui_settings.last_audio_update < 0.03 then
        return
    end
    ui_settings.last_audio_update = current_time
    ui_settings.audio_buffer = {}
    local ok_playing, is_playing = r.CF_Preview_GetValue(playback.playing_preview, "B_PLAYING")
    if not (ok_playing and is_playing) then
        waveform.current_pitch_note = "Not playing"
        return
    end
    local buf_l = r.new_array(ui_settings.buffer_size)
    local buf_r = r.new_array(ui_settings.buffer_size)
    local ok = r.CF_Preview_GetSamples(playback.playing_preview, 0, ui_settings.buffer_size, buf_l, buf_r)
    if ok and ok > 0 then
        waveform.current_pitch_note = "Got " .. ok .. " samples"
        for i = 1, math.min(ok, ui_settings.buffer_size) do
            local sample = buf_l[i] or 0
            ui_settings.audio_buffer[i] = math.max(-1, math.min(1, sample))
        end
        
        if current_time - waveform.last_pitch_update > 0.1 then
            if playback.playing_source then
                local sample_rate = r.GetMediaSourceSampleRate(playback.playing_source)
                if sample_rate and sample_rate > 0 and #ui_settings.audio_buffer > 0 then
                    local detected_freq = detect_pitch_autocorrelation(ui_settings.audio_buffer, sample_rate)
                    if detected_freq then
                        waveform.current_pitch_hz = detected_freq
                        waveform.current_pitch_note = freq_to_note(detected_freq)
                    else
                        waveform.current_pitch_hz = nil
                        waveform.current_pitch_note = string.format("BufSize:%d SR:%d", #ui_settings.audio_buffer, sample_rate)
                    end
                    waveform.last_pitch_update = current_time
                else
                    waveform.current_pitch_note = playback.playing_source and "No SR" or "No Source"
                end
            end
        end
    else
        ui_settings.audio_buffer = {} 
    end
end
local function read_directory_recursive(path, load_children)
    local cached = get_cached_tree(path)
    if cached then
        return cached
    end
    
    local items = {}
    local i = 0
    
    local max_depth = 5 
    local current_depth = select(2, path:gsub("[/\\]", ""))
    
    while true do
        local subdir = r.EnumerateSubdirectories(path, i)
        if not subdir then break end
        
        if not subdir:match("^%.") and not subdir:match("^__") then
            local sub_path = path .. sep .. subdir
            local sub_depth = select(2, sub_path:gsub("[/\\]", ""))
            
            local sub_items = {}
            if load_children and sub_depth - current_depth < max_depth then
                sub_items = read_directory_recursive(sub_path, false)  
            end
            
            table.insert(items, {
                name = subdir, 
                is_dir = true, 
                items = sub_items,
                path = sub_path,  
                children_loaded = load_children or false
            })
        end
        i = i + 1
        
        if i > 1000 then break end
    end
    
    local j = 0
    local file_count = 0
    local max_files_per_folder = 500  
    
    while file_count < max_files_per_folder do
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
           file:match("%.jpg$") or
           file:match("%.jpeg$") or
           file:match("%.png$") or
           file:match("%.gif$") or
           file:match("%.bmp$") or
           file:match("%.mp4$") or
           file:match("%.mov$") or
           file:match("%.avi$") or
           file:match("%.wmv$") or
           file:match("%.mkv$") then
            table.insert(items, {name = file, is_dir = false})
            file_count = file_count + 1
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
    
    set_cached_tree(path, items)
    
    return items
end

local function get_flat_file_list(location)
    if location ~= search_filter.cached_location or #search_filter.cached_flat_files == 0 then
        clear_sort_cache()  
        local files, timestamps, cache_time, metadata = load_file_cache(location)
        if files then
            search_filter.cached_flat_files = files
            search_filter.cached_location = location
            search_filter.filtered_files = search_filter.cached_flat_files
            if not cache_mgmt.loading_files then
                cached_metadata = metadata or {}
            end
        else
            search_filter.cached_flat_files = {}
            search_filter.cached_location = location
            search_filter.filtered_files = {}
            if not cache_mgmt.loading_files then
                cached_metadata = {}
            end
        end
    end
    
    if search_filter.filtered_files and #search_filter.filtered_files > 0 then
        return search_filter.filtered_files
    else
        return search_filter.cached_flat_files
    end
end

local function set_track_color(track, color_hex)
    local color = tonumber(color_hex:gsub("#",""), 16)
    r.SetTrackColor(track, color)
end

local function get_reference_file_path()
    if playback.current_playing_file and playback.current_playing_file ~= "" then
        return playback.current_playing_file
    end
    if playback.last_displayed_file and playback.last_displayed_file ~= "" then
        return playback.last_displayed_file
    end
    if ui and ui.visible_files and ui.selected_index and ui.visible_files[ui.selected_index] then
        local entry = ui.visible_files[ui.selected_index]
        return entry.full_path or entry.path
    end
    return nil
end

local function get_sync_base_rate(reference_path)
    if playback.playing_source then
        local _, rate = r.GetTempoMatchPlayRate(playback.playing_source, 1, 0, 1)
        if rate and rate > 0 then return rate end
    end

    local file_path = reference_path or get_reference_file_path()
    if not file_path or file_path == "" then return nil end
    if is_video_or_image_file(file_path) then return nil end

    local ext = file_path:match("%.([^%.]+)$")
    if ext then
        ext = ext:lower()
        if ext == "mid" or ext == "midi" then
            return nil
        end
    end

    local source = r.PCM_Source_CreateFromFile(file_path)
    if not source then return nil end

    local base_rate
    local _, rate = r.GetTempoMatchPlayRate(source, 1, 0, 1)
    if rate and rate > 0 then
        base_rate = rate
    end
    r.PCM_Source_Destroy(source)
    return base_rate
end

local function update_playrate(new_effective_rate, base_rate_override)
    playback.effective_playrate = new_effective_rate
    
    if playback.use_original_speed then
        playback.current_playrate = new_effective_rate
    else
        local base_rate = base_rate_override
        if not base_rate or base_rate <= 0 then
            base_rate = get_sync_base_rate()
        end
        if base_rate and base_rate > 0 then
            playback.current_playrate = new_effective_rate / base_rate
        else
            playback.current_playrate = new_effective_rate
        end
    end
    
    if playback.playing_preview and not playback.is_paused then
        r.CF_Preview_SetValue(playback.playing_preview, "D_PLAYRATE", playback.effective_playrate)
    end
    update_monitor_positions()
end

local function refresh_effective_playrate(reference_path)
    local file_path = reference_path or get_reference_file_path()
    if not file_path or file_path == "" then
        return false
    end

    local multiplier = playback.current_playrate or 1.0
    local base_rate = nil
    local effective = multiplier

    if not playback.use_original_speed then
        base_rate = get_sync_base_rate(file_path)
        if base_rate and base_rate > 0 then
            effective = base_rate * multiplier
        end
    end

    update_playrate(effective, base_rate)
    playback.pending_sync_refresh = false
    if not playback.use_original_speed then
        playback.last_sync_reference = file_path
    else
        playback.last_sync_reference = nil
    end

    return true
end

local function get_cached_file_length(file_path)
    if not file_path or file_path == "" then
        return 0
    end
    
    if is_video_or_image_file(file_path) then
        return 0
    end
    
    if waveform.cached_length_file == file_path and waveform.cached_length > 0 then
        return waveform.cached_length
    end
    
    local source = r.PCM_Source_CreateFromFile(file_path)
    if source then
        local length = r.GetMediaSourceLength(source)
        
        local ext = file_path:match("%.([^%.]+)$")
        if ext then
            ext = ext:lower()
            if ext == "mid" or ext == "midi" then
                length = length / 2
            end
        end
        
        r.PCM_Source_Destroy(source)
        if length and length > 0 then
            waveform.cached_length = length
            waveform.cached_length_file = file_path
            return length
        end
    end
    
    return 0
end

local function get_file_display_length(file_path)
    if not file_path or file_path == "" then
        return 0
    end
    
    return get_cached_file_length(file_path)
end

local function get_file_length(file_path)
    if not file_path or file_path == "" then
        return 0
    end
    local source = r.PCM_Source_CreateFromFile(file_path)
    if source then
        local length = r.GetMediaSourceLength(source)
        r.PCM_Source_Destroy(source)
        return length or 0
    end
    return 0
end
local function stop_playback(is_loop_restart)
    local was_track_playback = playback.is_video_playback or playback.is_midi_playback
    
    if playback.is_video_playback or playback.is_midi_playback then
        r.Main_OnCommand(1016, 0)  
        if playback.video_preview_item and playback.video_preview_track then
            safe_delete_media_item(playback.video_preview_track, playback.video_preview_item)
            r.SetMediaTrackInfo_Value(playback.video_preview_track, "I_SOLO", 0)
        end
        playback.video_preview_item = nil
        playback.is_video_playback = false
        playback.is_midi_playback = false
        playback.playing_source = nil
    end
    
    if playback.playing_preview then
        r.CF_Preview_Stop(playback.playing_preview)
        playback.playing_preview = nil
    else
        r.CF_Preview_StopAll()
    end
    
    if playback.playing_source and not was_track_playback then
        r.PCM_Source_Destroy(playback.playing_source)
        playback.playing_source = nil
    elseif was_track_playback then
        playback.playing_source = nil
    end
    if not is_loop_restart then
        playback.playing_path = nil
    end
    playback.is_paused = false
    playback.paused_position = 0
    
    -- Reset pitch detection
    waveform.current_pitch_hz = nil
    waveform.current_pitch_note = nil
    waveform.last_pitch_update = 0
    
    if waveform.monitor_sel_start and waveform.monitor_sel_end and math.abs(waveform.monitor_sel_end - waveform.monitor_sel_start) > 0.01 then
        playback.prev_play_cursor = waveform.monitor_sel_start
    else
        playback.prev_play_cursor = 0
    end
end
local function start_playback(file_path)
    if playback.link_transport then
        local reaper_playing = r.GetPlayState() & 1 == 1
        if reaper_playing then
            r.Main_OnCommand(1016, 0)  
        end
    end
    
    local saved_paused_pos = playback.paused_position
    local was_paused = playback.is_paused
    local paused_file = playback.current_playing_file
    
    stop_playback(false)
    
    local resuming_paused = was_paused and paused_file == file_path and saved_paused_pos and saved_paused_pos > 0
    
    local has_selection = (waveform.monitor_sel_start ~= waveform.monitor_sel_end) and (waveform.monitor_sel_end > 0) and (waveform.monitor_file_path == file_path)
    local source = r.PCM_Source_CreateFromFile(file_path)
    if not source then return end
    playback.playing_source = source
    playback.playing_preview = r.CF_CreatePreview(source)
    if not playback.playing_preview then 
        r.PCM_Source_Destroy(source)
        playback.playing_source = nil
        return 
    end
    r.CF_Preview_SetValue(playback.playing_preview, "D_VOLUME", playback.preview_volume)
    r.CF_Preview_SetValue(playback.playing_preview, "B_LOOP", playback.loop_play and 1 or 0)
    r.CF_Preview_SetValue(playback.playing_preview, "D_PITCH", playback.current_pitch)
    
    local ext = file_path:match("%.([^%.]+)$")
    if ext then ext = ext:lower() end
    local file_type = file_types[ext]
    local is_video = (file_type == "REAPER_VIDEOFOLDER")
    local is_midi = (ext == "mid" or ext == "midi")
    
    if is_video or is_midi then
        
        r.CF_Preview_Stop(playback.playing_preview)
        playback.playing_preview = nil
        
        local track_count = r.CountTracks(0)
        local preview_track_obj = nil
        
        if is_midi and ui_settings.use_selected_track_for_midi then
            preview_track_obj = r.GetSelectedTrack(0, 0)
            if not preview_track_obj then
                waveform.midi_info_message = "No track selected!\nPlease select a track for MIDI playback."
                return
            end
            waveform.midi_info_message = nil
        else
            local track_name = "__MEDIA_PREVIEW__"
            
            for i = 0, track_count - 1 do
                local track = r.GetTrack(0, i)
                local _, name = r.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
                if name == track_name then
                    preview_track_obj = track
                    break
                end
            end
        
        if not preview_track_obj then
            r.InsertTrackAtIndex(track_count, false)
            preview_track_obj = r.GetTrack(0, track_count)
            r.GetSetMediaTrackInfo_String(preview_track_obj, "P_NAME", track_name, true)
            
            local red_color = r.ColorToNative(255, 0, 0)|0x1000000 
            
            if is_midi then
                r.SetMediaTrackInfo_Value(preview_track_obj, "B_SHOWINMIXER", 1)
                r.SetMediaTrackInfo_Value(preview_track_obj, "B_SHOWINTCP", 1)
            else
                r.SetMediaTrackInfo_Value(preview_track_obj, "B_SHOWINMIXER", 0)
                r.SetMediaTrackInfo_Value(preview_track_obj, "B_SHOWINTCP", 0)
            end
            track_count = r.CountTracks(0)
            
            if is_midi and not ui_settings.use_selected_track_for_midi then
                local synth_name = ui_settings.use_numaplayer and "Numa Player" or "ReaSynth (Cockos)"
                local fx_index = r.TrackFX_AddByName(preview_track_obj, synth_name, false, -1)
                if fx_index >= 0 then
                    if ui_settings.use_numaplayer then
                        r.TrackFX_Show(preview_track_obj, fx_index, 3)  
                    else
                        r.TrackFX_Show(preview_track_obj, fx_index, 2)  
                    end
                elseif ui_settings.use_numaplayer then
                    r.ShowMessageBox("Numa Player is not installed or not found.\nFalling back to ReaSynth for MIDI playback.", "MIDI Synth Not Found", 0)
                    fx_index = r.TrackFX_AddByName(preview_track_obj, "ReaSynth (Cockos)", false, -1)
                    if fx_index >= 0 then
                        r.TrackFX_Show(preview_track_obj, fx_index, 2)
                    end
                end
            end
        else
            if is_midi and not ui_settings.use_selected_track_for_midi then
                local synth_name = ui_settings.use_numaplayer and "Numa Player" or "ReaSynth"
                local wrong_synth_name = ui_settings.use_numaplayer and "ReaSynth" or "Numa Player"
                local has_correct_synth = false
                local fx_count = r.TrackFX_GetCount(preview_track_obj)
                
                for i = fx_count - 1, 0, -1 do
                    local _, fx_name = r.TrackFX_GetFXName(preview_track_obj, i, "")
                    if fx_name:match(synth_name) then
                        has_correct_synth = true
                    elseif fx_name:match(wrong_synth_name) then
                        r.TrackFX_Delete(preview_track_obj, i)
                    end
                end
                
                if not has_correct_synth then
                    local full_synth_name = ui_settings.use_numaplayer and "Numa Player" or "ReaSynth (Cockos)"
                    local fx_index = r.TrackFX_AddByName(preview_track_obj, full_synth_name, false, -1)
                    if fx_index >= 0 then
                        if ui_settings.use_numaplayer then
                            r.TrackFX_Show(preview_track_obj, fx_index, 3) 
                        else
                            r.TrackFX_Show(preview_track_obj, fx_index, 2) 
                        end
                    elseif ui_settings.use_numaplayer then
                        r.ShowMessageBox("Numa Player is not installed or not found.\nFalling back to ReaSynth for MIDI playback.", "MIDI Synth Not Found", 0)
                        fx_index = r.TrackFX_AddByName(preview_track_obj, "ReaSynth (Cockos)", false, -1)
                        if fx_index >= 0 then
                            r.TrackFX_Show(preview_track_obj, fx_index, 2)
                        end
                        end
                    end
                end
            end
        end
        
        if playback.use_exclusive_solo then
            r.SetMediaTrackInfo_Value(preview_track_obj, "I_SOLO", 1)
        end        local item_count = r.CountTrackMediaItems(preview_track_obj)        
        for i = item_count - 1, 0, -1 do
            local item = r.GetTrackMediaItem(preview_track_obj, i)
            r.DeleteTrackMediaItem(preview_track_obj, item)
        end
        
        local item, length
        
        if is_midi then
            r.SetOnlyTrackSelected(preview_track_obj)
            r.SetEditCurPos(0, false, false)
            
            local item_count_before = r.CountTrackMediaItems(preview_track_obj)
            
            r.InsertMedia(file_path, 0) 
            
            local item_count_after = r.CountTrackMediaItems(preview_track_obj)
            if item_count_after > item_count_before then
                item = r.GetTrackMediaItem(preview_track_obj, item_count_after - 1)
                length = r.GetMediaItemInfo_Value(item, "D_LENGTH")
                r.SetMediaItemPosition(item, 0, false)
                r.UpdateItemInProject(item)
            else
                item = r.AddMediaItemToTrack(preview_track_obj)
                local take = r.AddTakeToMediaItem(item)
                r.SetMediaItemTake_Source(take, source)
                length = r.GetMediaSourceLength(source)
                if length > 0 then
                    length = length / 2
                else
                    length = 60
                end
                r.SetMediaItemPosition(item, 0, false)
                r.SetMediaItemLength(item, length, false)
            end
        else
            item = r.AddMediaItemToTrack(preview_track_obj)
            local take = r.AddTakeToMediaItem(item)
            r.SetMediaItemTake_Source(take, source)
            length = r.GetMediaSourceLength(source)
            r.SetMediaItemPosition(item, 0, false)
            r.SetMediaItemLength(item, length, false)
        end
        
        r.UpdateItemInProject(item)
        
        if is_midi then
            waveform.midi_info_message = nil
        end
        
        playback.video_preview_track = preview_track_obj
        playback.video_preview_item = item
        playback.is_video_playback = is_video
        playback.is_midi_playback = is_midi
        playback.current_playing_file = file_path
        playback.playing_path = file_path
        playback.last_displayed_file = file_path  
        
        r.GetSet_LoopTimeRange(true, false, 0, length, false)
        
        local start_pos = 0
        if waveform.play_cursor_position > 0 then
            start_pos = waveform.play_cursor_position * length
        end
        
        if playback.loop_play then
            r.GetSet_LoopTimeRange(true, true, 0, length, false)  
            local loop_state = r.GetSetRepeat(1)  
        else
            r.GetSet_LoopTimeRange(true, true, 0, length, false)  
            r.GetSetRepeat(0) 
        end
        
        r.SetEditCurPos(start_pos, false, false)
        r.UpdateArrange()  
        r.Main_OnCommand(1007, 0)  
        return  
    end
    
    if playback.use_original_speed then
        playback.effective_playrate = playback.current_playrate or 1.0
        r.CF_Preview_SetValue(playback.playing_preview, "D_PLAYRATE", playback.effective_playrate)
    else
        local tempo = r.Master_GetTempo()
        local _, base_rate = r.GetTempoMatchPlayRate(source, 1, 0, 1)
        playback.effective_playrate = base_rate * (playback.current_playrate or 1.0)
        r.CF_Preview_SetValue(playback.playing_preview, "D_PLAYRATE", playback.effective_playrate)
    end
    update_monitor_positions()
    
    local start_pos = 0
    if resuming_paused then
        start_pos = saved_paused_pos
    elseif has_selection then
        start_pos = waveform.monitor_sel_start
    else
        local source_for_length = r.PCM_Source_CreateFromFile(file_path)
        if source_for_length then
            local file_length = r.GetMediaSourceLength(source_for_length)
            r.PCM_Source_Destroy(source_for_length)
            local adjusted_length = file_length / (playback.effective_playrate or 1.0)
            start_pos = waveform.play_cursor_position * adjusted_length
        end
    end
    
    r.CF_Preview_SetValue(playback.playing_preview, "D_POSITION", start_pos)
    
    if playback.link_transport then
        local project_start_pos
        if playback.link_start_from_editcursor then
            project_start_pos = r.GetCursorPosition()
        else
            project_start_pos = start_pos
            r.SetEditCurPos(project_start_pos, false, false)
        end
        
        local reaper_state = r.GetPlayState()
        if reaper_state & 1 == 0 then
            r.CSurf_OnPlay()
            
            local max_wait = 50  
            local wait_count = 0
            while wait_count < max_wait do
                local current_state = r.GetPlayState()
                if current_state & 1 == 1 then  
                    break
                end
                wait_count = wait_count + 1
                local start_time = r.time_precise()
                while r.time_precise() - start_time < 0.001 do end  
            end
        end
    end
    
    r.CF_Preview_Play(playback.playing_preview)
    
    playback.is_paused = false
    playback.current_playing_file = file_path
    playback.playing_path = file_path
    playback.last_displayed_file = file_path
    playback.prev_play_cursor = start_pos
    playback.paused_position = 0
    
    if not has_selection then
        waveform.monitor_file_path = file_path
    end
end
local function pause_playback()
    if playback.is_video_playback or playback.is_midi_playback then
        local play_state = r.GetPlayState()
        if play_state & 1 == 1 then
            r.Main_OnCommand(1008, 0)
            playback.is_paused = true
        elseif play_state & 2 == 2 then
            r.Main_OnCommand(1007, 0)
            playback.is_paused = false
        end
        return
    end
    if not playback.playing_preview and not playback.is_paused then return end
    
    if not playback.is_paused then
        local ok, pos = r.CF_Preview_GetValue(playback.playing_preview, "D_POSITION")
        if ok then
            playback.paused_position = pos
            playback.prev_play_cursor = pos
        end
        
        if playback.link_transport then
            playback.paused_project_position = r.GetPlayPosition()
        end
        
        r.CF_Preview_Stop(playback.playing_preview)
        playback.playing_preview = nil
        playback.is_paused = true
        
        if playback.link_transport then
            local project_playing = (r.GetPlayState() & 1) == 1
            if project_playing then
                r.CSurf_OnPause()
            end
        end
        
    else
        if playback.playing_source and playback.paused_position then
            playback.playing_preview = r.CF_CreatePreview(playback.playing_source)
            if playback.playing_preview then
                r.CF_Preview_SetValue(playback.playing_preview, "D_VOLUME", playback.preview_volume)
                r.CF_Preview_SetValue(playback.playing_preview, "B_LOOP", playback.loop_play and 1 or 0)
                r.CF_Preview_SetValue(playback.playing_preview, "D_PITCH", playback.current_pitch)
                r.CF_Preview_SetValue(playback.playing_preview, "D_PLAYRATE", playback.effective_playrate or 1.0)
                r.CF_Preview_SetValue(playback.playing_preview, "D_POSITION", playback.paused_position)
                
                if playback.link_transport then
                    local resume_position = playback.paused_project_position or playback.paused_position
                    r.SetEditCurPos(resume_position, false, false)
                    
                    local project_state = r.GetPlayState()
                    if project_state & 1 == 0 then
                        r.CSurf_OnPlay()
                    end
                end
                
                r.CF_Preview_Play(playback.playing_preview)
                playback.prev_play_cursor = playback.paused_position  
                playback.is_paused = false
            end
        end
    end
end

local function play_media(file_path)
    if file_path ~= waveform.monitor_file_path and waveform.monitor_file_path ~= "" then
        waveform.monitor_sel_start = 0
        waveform.monitor_sel_end = 0
        waveform.normalized_sel_start = 0
        waveform.normalized_sel_end = 0
        waveform.monitor_file_path = ""
        waveform.selection_start = 0
        waveform.selection_end = 0
        waveform.selection_active = false
    end
    start_playback(file_path)
end

local function monitor_transport_state()
    if not playback.link_transport then 
        return 
    end
    
    local current_state = r.GetPlayState()
    local is_playing = (current_state & 1) == 1
    local is_paused = (current_state & 2) == 2
    
    if is_playing and (playback.last_transport_state & 1) == 0 then
        if playback.is_paused and playback.playing_source then
            pause_playback() 
        elseif playback.current_playing_file and playback.current_playing_file ~= "" and not playback.playing_preview then
            play_media(playback.current_playing_file)
        end
    elseif is_paused and (playback.last_transport_state & 2) == 0 then
        if playback.playing_preview and not playback.is_paused then
            pause_playback()  
        end
    elseif not is_playing and not is_paused and (playback.last_transport_state & 1) == 1 then
        if playback.playing_preview or playback.is_paused then
            stop_playback(false)  
        end
    end
    
    playback.last_transport_state = current_state
end

local function sync_transport_with_preview()
    if not playback.link_transport or not playback.playing_preview or playback.is_paused then
        return
    end
    
    if playback.is_video_playback or playback.is_midi_playback then
        return
    end

end
local function update_monitor_positions()
    if waveform.normalized_sel_start >= 0 and waveform.normalized_sel_end > waveform.normalized_sel_start and waveform.monitor_file_path ~= "" then
        local source = r.PCM_Source_CreateFromFile(waveform.monitor_file_path)
        if source then
            local file_length = r.GetMediaSourceLength(source)
            r.PCM_Source_Destroy(source)
            if file_length and file_length > 0 then
                waveform.monitor_sel_start = waveform.normalized_sel_start * file_length / (playback.effective_playrate or 1.0)
                waveform.monitor_sel_end = waveform.normalized_sel_end * file_length / (playback.effective_playrate or 1.0)
            end
        end
    end

    local r = 0
    local g = 0
    local b = 0
    local progress = 0
    if waveform.selection_active and waveform.normalized_sel_start and waveform.normalized_sel_end then
        progress = math.abs(waveform.normalized_sel_end - waveform.normalized_sel_start)
    end
    progress = math.max(0, math.min(1, progress))
    if progress < 0.5 then
        r = math.floor(255 * (progress * 2))
        g = 255
    else
        r = 255
        g = math.floor(255 * (1 - (progress - 0.5) * 2))
    end
    r = math.floor(math.max(0, math.min(255, r)))
    g = math.floor(math.max(0, math.min(255, g)))
    return (r << 24) | (g << 16) | (b << 8) | 0xFF
end
local function draw_playback_position()
end
local function handle_drag_drop(file_path)
    if r.ImGui_BeginDragDropSource(ctx, r.ImGui_DragDropFlags_SourceAllowNullID()) then
        insert_state.drop_file = file_path
        local ext = file_path:match("%.([^%.]+)$"):lower()
        insert_state.is_midi = (ext == "mid" or ext == "midi")
        r.ImGui_SetDragDropPayload(ctx, "REAPER_MEDIAFOLDER", file_path)
        r.ImGui_Text(ctx, "Drag to Track: " .. file_path)
        r.ImGui_EndDragDropSource(ctx)
    end
end
local function insert_media_on_track(file_path, track, use_original_speed, custom_playrate, custom_pitch)
    if not track then return end
    generate_peak_file(file_path)
    local ext = file_path:match("%.([^%.]+)$"):lower()
    local file_type = file_types[ext]
    local is_midi_file = insert_state.is_midi
    local item = r.AddMediaItemToTrack(track)
    if file_type == "REAPER_MEDIAFOLDER" then
        local take = r.AddTakeToMediaItem(item)
        local source = r.PCM_Source_CreateFromFile(file_path)
        r.SetMediaItemTake_Source(take, source)
        local cursor_pos = r.GetCursorPosition()
        r.SetMediaItemPosition(item, cursor_pos, false)
        
        local source_length = r.GetMediaSourceLength(source)
        
        if is_midi_file and source_length then
            source_length = source_length / 2
        end
        
        local has_selection = waveform.monitor_sel_start and waveform.monitor_sel_end and 
                            math.abs(waveform.monitor_sel_end - waveform.monitor_sel_start) > 0.01 and
                            waveform.monitor_file_path == file_path
        
        if has_selection then
            local sel_start = waveform.monitor_sel_start
            local sel_end = waveform.monitor_sel_end
            local sel_length = sel_end - sel_start
            
            local actual_start = sel_start * (playback.effective_playrate or 1.0)
            r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", actual_start)
            
            if use_original_speed then
                r.SetMediaItemLength(item, sel_length, false)
                r.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", custom_playrate)
            else
                if not is_midi_file then
                    local _, rate, len = r.GetTempoMatchPlayRate(source, 1, 0, 1)
                    r.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", rate)
                    r.SetMediaItemLength(item, sel_length, false)
                else
                    r.SetMediaItemLength(item, sel_length, false)
                    r.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", custom_playrate)
                end
            end
        else
            if use_original_speed then
                r.SetMediaItemLength(item, source_length / custom_playrate, false)
                r.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", custom_playrate)
            else
                if not is_midi_file then
                    local _, rate, len = r.GetTempoMatchPlayRate(source, 1, 0, 1)
                    r.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", rate)
                    r.SetMediaItemLength(item, len, false)
                else
                    r.SetMediaItemLength(item, source_length, false)
                    r.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", custom_playrate)
                end
            end
        end
        
        r.SetMediaItemTakeInfo_Value(take, "D_PITCH", custom_pitch)
    elseif file_type == "REAPER_IMAGEFOLDER" or file_type == "REAPER_VIDEOFOLDER" then
        local take = r.AddTakeToMediaItem(item)
        r.SetMediaItemTake_Source(take, r.PCM_Source_CreateFromFile(file_path))
        local cursor_pos = r.GetCursorPosition()
        r.SetMediaItemPosition(item, cursor_pos, false)
        r.SetMediaItemLength(item, 5.0, false)
    end
    if insert_state.disable_fades then
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
    if mouse_state == 1 and insert_state.drop_file then
        insert_state.is_dragging = true
        insert_state.drop_track = r.GetTrackFromPoint(r.GetMousePosition())
    elseif mouse_state == 0 and insert_state.is_dragging then
        if insert_state.drop_file and insert_state.drop_track then
            insert_media_on_track(insert_state.drop_file, insert_state.drop_track, playback.use_original_speed, playback.current_playrate, playback.current_pitch)
        else
        end
        insert_state.is_dragging = false
        insert_state.drop_file = nil
        insert_state.drop_track = nil
    end
end

local function insert_with_reasamplomatic(file_path)
    local ext = file_path:match("%.([^%.]+)$")
    if not ext then return end
    ext = ext:lower()
    
    if ext == "mid" or ext == "midi" then
        return
    end
    
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    
    local track_idx = r.CountTracks(0)
    r.InsertTrackAtIndex(track_idx, true)
    local track = r.GetTrack(0, track_idx)
    
    if not track then
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("Insert with ReaSamplomatic5000", -1)
        return
    end
    
    local item_name = file_path:match("([^/\\]+)$")
    if item_name then
        local name_without_ext = item_name:match("(.+)%..+$") or item_name
        r.GetSetMediaTrackInfo_String(track, "P_NAME", name_without_ext, true)
    end
    
    local fx_idx = r.TrackFX_AddByName(track, "ReaSamploMatic5000", false, -1)
    
    if fx_idx >= 0 then
        r.TrackFX_SetNamedConfigParm(track, fx_idx, "FILE0", file_path)
        r.TrackFX_SetNamedConfigParm(track, fx_idx, "DONE", "")
    end
    
    r.PreventUIRefresh(-1)
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
    r.Undo_EndBlock("Insert with ReaSamplomatic5000", -1)
end

local function replace_reasamplomatic_sample(file_path)
    local ext = file_path:match("%.([^%.]+)$")
    if not ext then return end
    ext = ext:lower()
    
    if ext == "mid" or ext == "midi" then
        return
    end
    
    local track = r.GetSelectedTrack(0, 0)
    if not track then
        r.MB("No track selected. Please select a track with ReaSamplomatic5000.", "Error", 0)
        return
    end
    
    local fx_count = r.TrackFX_GetCount(track)
    local rs5k_idx = -1
    
    for i = 0, fx_count - 1 do
        local _, fx_name = r.TrackFX_GetFXName(track, i, "")
        if fx_name:match("ReaSamploMatic5000") or fx_name:match("RS5K") then
            rs5k_idx = i
            break
        end
    end
    
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    
    if rs5k_idx == -1 then
        rs5k_idx = r.TrackFX_AddByName(track, "ReaSamploMatic5000", false, -1)
        if rs5k_idx < 0 then
            r.PreventUIRefresh(-1)
            r.MB("Failed to add ReaSamplomatic5000 to selected track.", "Error", 0)
            r.Undo_EndBlock("Replace ReaSamplomatic5000 sample", -1)
            return
        end
    end
    
    r.TrackFX_SetNamedConfigParm(track, rs5k_idx, "FILE0", file_path)
    r.TrackFX_SetNamedConfigParm(track, rs5k_idx, "DONE", "")
    
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    r.Undo_EndBlock("Replace ReaSamplomatic5000 sample", -1)
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

local function get_audio_data()
    if use_cf_view and CF_Preview then
        local retval, pos = r.CF_Preview_GetValue(CF_Preview, "D_POSITION")
        local source = r.PCM_Source_CreateFromFile(playback.current_playing_file)
        if source then
            local samplerate = r.GetMediaSourceSampleRate(source)
            local samplebuffer = r.new_array(ui_settings.buffer_size * 2)
            r.PCM_Source_GetPeaks(source, samplerate, pos, 1, ui_settings.buffer_size, 0, samplebuffer)
            for i = 1, ui_settings.buffer_size do
                ui_settings.audio_buffer[i] = samplebuffer[i*2-1] or 0
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
        local samplebuffer = r.new_array(ui_settings.buffer_size * 2)
        r.GetAudioAccessorSamples(accessor, samplerate, 1, playpos, ui_settings.buffer_size, samplebuffer)
        for i = 1, ui_settings.buffer_size do
            ui_settings.audio_buffer[i] = samplebuffer[i*2-1] or 0
        end
        r.DestroyAudioAccessor(accessor)
    end
end

local function draw_file_list()
    if file_location.current_location ~= "" then
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 0, 8)
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 2, 8)  
            local child_flags = r.ImGui_WindowFlags_HorizontalScrollbar() | r.ImGui_WindowFlags_NoBackground()
            if r.ImGui_BeginChild(ctx, "file_list", 0, 0, 1, child_flags) then
                local function folder_has_matching_files(items, search_lower)
                    if search_lower == "" then return true end
                    for _, item in ipairs(items) do
                        if item.is_dir then
                            if folder_has_matching_files(item.items or {}, search_lower) then
                                return true
                            end
                        else
                            local name_lower = item.name_lower or string.lower(item.name)
                            if string.find(name_lower, search_lower, 1, true) then
                                return true
                            end
                        end
                    end
                    return false
                end
                local function display_tree(items, path)
                    local search_lower = search_filter.search_term ~= "" and string.lower(search_filter.search_term) or ""
                    for _, item in ipairs(items) do
                        local icon = item.is_dir and FOLDER_ICON or FILE_ICON
                        if item.is_dir then
                            if folder_has_matching_files(item.items or {}, search_lower) then
                                local tree_open = r.ImGui_TreeNode(ctx, icon .. " " .. item.name)
                                
                                if r.ImGui_IsItemFocused(ctx) then
                                    if playback.auto_play and (playback.playing_preview or playback.is_midi_playback or playback.is_video_playback) then
                                        stop_playback()
                                    end
                                    playback.selected_file = ""
                                    ui.selected_index = 0
                                end
                                
                                r.ImGui_SameLine(ctx)
                                
                                local button_id = "##add_folder_" .. path .. sep .. item.name
                                local button_size = 16
                                local cursor_x, cursor_y = r.ImGui_GetCursorScreenPos(ctx)
                                
                                if r.ImGui_InvisibleButton(ctx, button_id, button_size, button_size) then
                                    local full_path = path .. sep .. item.name
                                    if not table.contains(file_location.locations, full_path) then
                                        table.insert(file_location.locations, full_path)
                                        save_locations()
                                    end
                                end
                                
                                if r.ImGui_IsItemHovered(ctx) then
                                    r.ImGui_SetTooltip(ctx, "Add this folder to Folders list")
                                end
                                
                                local drawList = r.ImGui_GetWindowDrawList(ctx)
                                local accent_color = hsv_to_color(ui_settings.accent_hue, 0.8, 0.9)
                                local hover_color = hsv_to_color(ui_settings.accent_hue, 1.0, 1.0)
                                local plus_color = r.ImGui_IsItemHovered(ctx) and hover_color or accent_color
                                
                                local center_x = cursor_x + button_size * 0.5
                                local center_y = cursor_y + button_size * 0.5
                                local plus_size = button_size * 0.4
                                
                                r.ImGui_DrawList_AddLine(drawList, center_x - plus_size, center_y, center_x + plus_size, center_y, plus_color, 2)
                                r.ImGui_DrawList_AddLine(drawList, center_x, center_y - plus_size, center_x, center_y + plus_size, plus_color, 2)
                                
                                if tree_open then
                                    if not item.children_loaded then
                                        local sub_path = item.path or (path .. sep .. item.name)
                                        item.items = read_directory_recursive(sub_path, true)
                                        item.children_loaded = true
                                    end
                                    display_tree(item.items, path .. sep .. item.name)
                                    r.ImGui_TreePop(ctx)
                                end
                            end
                        else
                            local show_file = true
                            if search_lower ~= "" then
                                local name_lower = string.lower(item.name)
                                show_file = string.find(name_lower, search_lower) ~= nil
                            end
                            if show_file then
                                local file_path = path .. sep .. item.name
                                if item.name == playback.selected_file then
                                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFFFFFFFF)
                                    ui_settings.pushed_color = 1
                                end
                                if r.ImGui_Selectable(ctx, icon .. " " .. item.name, item.name == playback.selected_file) then
                                    if not playback.auto_play and playback.current_playing_file ~= file_path then
                                        if playback.playing_preview or playback.is_midi_playback or playback.is_video_playback then
                                            stop_playback()
                                        end
                                    end
                                    
                                    playback.selected_file = item.name
                                    playback.current_playing_file = file_path
                                    
                                    waveform.selection_active = false
                                    waveform.is_dragging = false
                                    waveform.selection_start = 0
                                    waveform.selection_end = 0
                                    waveform.monitor_sel_start = 0
                                    waveform.monitor_sel_end = 0
                                    waveform.normalized_sel_start = 0
                                    waveform.normalized_sel_end = 0
                                    waveform.monitor_file_path = ""
                                    waveform.play_cursor_position = 0 
                                    
                                    for i, file in ipairs(ui.visible_files) do
                                        if file.name == item.name and file.path == file_path then
                                            ui.selected_index = i
                                            break
                                        end
                                    end
                                    if playback.auto_play then
                                        play_media(file_path)
                                    end
                                end
                                
                                if r.ImGui_IsItemFocused(ctx) and playback.selected_file ~= item.name then
                                    playback.selected_file = item.name
                                    playback.current_playing_file = file_path
                                    
                                    waveform.selection_active = false
                                    waveform.is_dragging = false
                                    waveform.selection_start = 0
                                    waveform.selection_end = 0
                                    waveform.monitor_sel_start = 0
                                    waveform.monitor_sel_end = 0
                                    waveform.normalized_sel_start = 0
                                    waveform.normalized_sel_end = 0
                                    waveform.monitor_file_path = ""
                                    waveform.play_cursor_position = 0
                                    
                                    for i, file in ipairs(ui.visible_files) do
                                        if file.name == item.name and file.path == file_path then
                                            ui.selected_index = i
                                            break
                                        end
                                    end
                                    
                                    if playback.auto_play then
                                        play_media(file_path)
                                    end
                                end
                                
                                if r.ImGui_BeginPopupContextItem(ctx, "tree_file_context_" .. item.name) then
                                    if #file_location.collections == 0 then
                                        load_collections()
                                    end
                                    
                                    if ui.current_view_mode == "collections" and file_location.selected_collection then
                                        if r.ImGui_MenuItem(ctx, "Remove from Collection") then
                                            for idx, f in ipairs(file_location.current_files) do
                                                if f.full_path == file_path then
                                                    remove_file_from_collection(file_location.selected_collection, idx)
                                                    clear_sort_cache()  
                                                    local db_data = load_collection(file_location.selected_collection)
                                                    if db_data and db_data.items then
                                                        file_location.current_files = {}
                                                        search_filter.cached_flat_files = {}
                                                        for _, item in ipairs(db_data.items) do
                                                            local file_entry = {
                                                                name = item.path:match("([^/\\]+)$"),
                                                                full_path = item.path,
                                                                is_dir = false
                                                            }
                                                            table.insert(file_location.current_files, file_entry)
                                                            table.insert(search_filter.cached_flat_files, file_entry)
                                                        end
                                                        search_filter.filtered_files = search_filter.cached_flat_files
                                                    end
                                                    break
                                                end
                                            end
                                        end
                                        r.ImGui_Separator(ctx)
                                    end
                                    
                                    local ext = file_path:match("%.([^%.]+)$")
                                    if ext then
                                        ext = ext:lower()
                                        if ext ~= "mid" and ext ~= "midi" then
                                            if r.ImGui_MenuItem(ctx, "Add to new track with ReaSamplomatic5000") then
                                                insert_with_reasamplomatic(file_path)
                                            end
                                            if r.ImGui_MenuItem(ctx, "Replace or add sample on selected track") then
                                                replace_reasamplomatic_sample(file_path)
                                            end
                                            r.ImGui_Separator(ctx)
                                        end
                                    end
                                    
                                    r.ImGui_Text(ctx, "Add to Collection:")
                                    r.ImGui_Separator(ctx)
                                    
                                    if #file_location.collections > 0 then
                                        for _, db_name in ipairs(file_location.collections) do
                                            local db = load_collection(db_name)
                                            if db and db.categories and #db.categories > 0 then
                                                if r.ImGui_BeginMenu(ctx, db_name .. " >>") then
                                                    if r.ImGui_MenuItem(ctx, "No Category") then
                                                        add_file_to_collection(db_name, file_path, nil)
                                                    end
                                                    r.ImGui_Separator(ctx)
                                                    for _, cat in ipairs(db.categories) do
                                                        if r.ImGui_MenuItem(ctx, cat) then
                                                            add_file_to_collection(db_name, file_path, {cat})
                                                        end
                                                    end
                                                    r.ImGui_EndMenu(ctx)
                                                end
                                            else
                                                if r.ImGui_MenuItem(ctx, db_name) then
                                                    add_file_to_collection(db_name, file_path, nil)
                                                end
                                            end
                                        end
                                        r.ImGui_Separator(ctx)
                                    end
                                    
                                    if r.ImGui_MenuItem(ctx, "+ New Collection...") then
                                        local retval, new_db_name = r.GetUserInputs("New Collection", 1, "Collection Name:", "")
                                        if retval and new_db_name ~= "" then
                                            create_new_collection(new_db_name)
                                            add_file_to_collection(new_db_name, file_path)
                                            load_collections()
                                        end
                                    end
                                    
                                    r.ImGui_EndPopup(ctx)
                                end
                                
                                if ui_settings.pushed_color > 0 then
                                    r.ImGui_PopStyleColor(ctx)
                                    ui_settings.pushed_color = 0
                                end
                                handle_drag_drop(file_path)
                            end
                        end
                    end
                end
                if file_location.flat_view then
                    local flat_files
                    if ui.current_view_mode == "collections" then
                        flat_files = search_filter.filtered_files
                    else
                        if file_location.current_location ~= search_filter.cached_location or #search_filter.cached_flat_files == 0 then
                            flat_files = get_flat_file_list(file_location.current_location)
                        else
                            flat_files = search_filter.cached_flat_files
                        end
                    end
                    
                    local table_flags = r.ImGui_TableFlags_Resizable() |
                                       r.ImGui_TableFlags_Sortable() |
                                       r.ImGui_TableFlags_RowBg() |
                                       r.ImGui_TableFlags_BordersOuter() |
                                       r.ImGui_TableFlags_BordersV() |
                                       r.ImGui_TableFlags_ScrollY()
                    
                    local header_bg_color = r.ImGui_ColorConvertDouble4ToU32(
                        ui_settings.window_bg_brightness * 0.8,
                        ui_settings.window_bg_brightness * 0.8,
                        ui_settings.window_bg_brightness * 0.8,
                        1.0
                    )
                    
                    local row_bg_1 = r.ImGui_ColorConvertDouble4ToU32(
                        ui_settings.window_bg_brightness * 0.95,
                        ui_settings.window_bg_brightness * 0.95,
                        ui_settings.window_bg_brightness * 0.95,
                        1.0
                    )
                    local row_bg_2 = r.ImGui_ColorConvertDouble4ToU32(
                        ui_settings.window_bg_brightness * 1.05,
                        ui_settings.window_bg_brightness * 1.05,
                        ui_settings.window_bg_brightness * 1.05,
                        1.0
                    )
                    
                    local accent_color = hsv_to_color(ui_settings.accent_hue, 1.0, 1.0, 0.4)  
                    local accent_hover_color = hsv_to_color(ui_settings.accent_hue, 0.8, 1.0, 0.3)  
                    local accent_active_color = hsv_to_color(ui_settings.accent_hue, 1.0, 0.8, 0.5)  
                    
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TableHeaderBg(), header_bg_color)
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TableRowBg(), row_bg_1)
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TableRowBgAlt(), row_bg_2)
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), accent_color)
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), accent_hover_color)
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), accent_active_color)
                    
                    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_CellPadding(), 4, 4)  
                    
                    local table_id = "files_table##" .. (file_location.current_location or "")
                    local col_count = get_visible_column_count()
                    if r.ImGui_BeginTable(ctx, table_id, col_count, table_flags) then
                        if ui_settings.visible_columns.name then
                            r.ImGui_TableSetupColumn(ctx, "Name", r.ImGui_TableColumnFlags_WidthStretch())
                        end
                        if ui_settings.visible_columns.type then
                            r.ImGui_TableSetupColumn(ctx, "Type", r.ImGui_TableColumnFlags_WidthFixed(), 50)
                        end
                        if ui_settings.visible_columns.size then
                            r.ImGui_TableSetupColumn(ctx, "Size", r.ImGui_TableColumnFlags_WidthFixed(), 70)
                        end
                        if ui_settings.visible_columns.duration then
                            r.ImGui_TableSetupColumn(ctx, "Duration", r.ImGui_TableColumnFlags_WidthFixed(), 60)
                        end
                        if ui_settings.visible_columns.sample_rate then
                            r.ImGui_TableSetupColumn(ctx, "SR", r.ImGui_TableColumnFlags_WidthFixed(), 50)
                        end
                        if ui_settings.visible_columns.channels then
                            r.ImGui_TableSetupColumn(ctx, "Ch", r.ImGui_TableColumnFlags_WidthFixed(), 50)
                        end
                        if ui_settings.visible_columns.bpm then
                            r.ImGui_TableSetupColumn(ctx, "BPM", r.ImGui_TableColumnFlags_WidthFixed(), 50)
                        end
                        if ui_settings.visible_columns.key then
                            r.ImGui_TableSetupColumn(ctx, "Key", r.ImGui_TableColumnFlags_WidthFixed(), 40)
                        end
                        if ui_settings.visible_columns.artist then
                            r.ImGui_TableSetupColumn(ctx, "Artist", r.ImGui_TableColumnFlags_WidthFixed(), 100)
                        end
                        if ui_settings.visible_columns.album then
                            r.ImGui_TableSetupColumn(ctx, "Album", r.ImGui_TableColumnFlags_WidthFixed(), 100)
                        end
                        if ui_settings.visible_columns.title then
                            r.ImGui_TableSetupColumn(ctx, "Title", r.ImGui_TableColumnFlags_WidthFixed(), 150)
                        end
                        if ui_settings.visible_columns.track then
                            r.ImGui_TableSetupColumn(ctx, "Track", r.ImGui_TableColumnFlags_WidthFixed(), 50)
                        end
                        if ui_settings.visible_columns.year then
                            r.ImGui_TableSetupColumn(ctx, "Year", r.ImGui_TableColumnFlags_WidthFixed(), 50)
                        end
                        if ui_settings.visible_columns.genre then
                            r.ImGui_TableSetupColumn(ctx, "Genre", r.ImGui_TableColumnFlags_WidthFixed(), 80)
                        end
                        if ui_settings.visible_columns.comment then
                            r.ImGui_TableSetupColumn(ctx, "Comment", r.ImGui_TableColumnFlags_WidthFixed(), 150)
                        end
                        if ui_settings.visible_columns.composer then
                            r.ImGui_TableSetupColumn(ctx, "Composer", r.ImGui_TableColumnFlags_WidthFixed(), 100)
                        end
                        if ui_settings.visible_columns.publisher then
                            r.ImGui_TableSetupColumn(ctx, "Publisher", r.ImGui_TableColumnFlags_WidthFixed(), 100)
                        end
                        if ui_settings.visible_columns.timesignature then
                            r.ImGui_TableSetupColumn(ctx, "Time Sig", r.ImGui_TableColumnFlags_WidthFixed(), 60)
                        end
                        if ui_settings.visible_columns.bitrate then
                            r.ImGui_TableSetupColumn(ctx, "Bitrate", r.ImGui_TableColumnFlags_WidthFixed(), 60)
                        end
                        if ui_settings.visible_columns.bitspersample then
                            r.ImGui_TableSetupColumn(ctx, "Bit Depth", r.ImGui_TableColumnFlags_WidthFixed(), 70)
                        end
                        if ui_settings.visible_columns.encoder then
                            r.ImGui_TableSetupColumn(ctx, "Encoder", r.ImGui_TableColumnFlags_WidthFixed(), 100)
                        end
                        if ui_settings.visible_columns.copyright then
                            r.ImGui_TableSetupColumn(ctx, "Copyright", r.ImGui_TableColumnFlags_WidthFixed(), 150)
                        end
                        if ui_settings.visible_columns.desc then
                            r.ImGui_TableSetupColumn(ctx, "Description", r.ImGui_TableColumnFlags_WidthFixed(), 150)
                        end
                        if ui_settings.visible_columns.originator then
                            r.ImGui_TableSetupColumn(ctx, "Originator", r.ImGui_TableColumnFlags_WidthFixed(), 100)
                        end
                        if ui_settings.visible_columns.originatorref then
                            r.ImGui_TableSetupColumn(ctx, "Orig Ref", r.ImGui_TableColumnFlags_WidthFixed(), 100)
                        end
                        if ui_settings.visible_columns.date then
                            r.ImGui_TableSetupColumn(ctx, "Date", r.ImGui_TableColumnFlags_WidthFixed(), 80)
                        end
                        if ui_settings.visible_columns.time then
                            r.ImGui_TableSetupColumn(ctx, "Time", r.ImGui_TableColumnFlags_WidthFixed(), 80)
                        end
                        if ui_settings.visible_columns.umid then
                            r.ImGui_TableSetupColumn(ctx, "UMID", r.ImGui_TableColumnFlags_WidthFixed(), 200)
                        end
                        r.ImGui_TableSetupScrollFreeze(ctx, 0, 1)
                        r.ImGui_TableHeadersRow(ctx)
                        
                        if r.ImGui_TableNeedSort and r.ImGui_TableGetColumnSortSpecs then
                            local need_sort, has_specs = r.ImGui_TableNeedSort(ctx)
                            if need_sort and has_specs then
                                local sort_specs_list = {}
                                local id = 0
                                while true do
                                    local rv, column_index, col_user_id, sort_direction = r.ImGui_TableGetColumnSortSpecs(ctx, id)
                                    if not rv then break end
                                    sort_specs_list[#sort_specs_list + 1] = {
                                        column_index = column_index,
                                        sort_direction = sort_direction
                                    }
                                    id = id + 1
                                end
                                
                                if #sort_specs_list > 0 then
                                    local spec = sort_specs_list[1]
                                    local column_index = spec.column_index
                                    local sort_direction = spec.sort_direction
                                    
                                    if column_index ~= search_filter.last_sort_column or 
                                       sort_direction ~= search_filter.last_sort_direction then
                                        
                                        search_filter.last_sort_column = column_index
                                        search_filter.last_sort_direction = sort_direction
                                        
                                        search_filter.sorted_files = {}
                                        for i, file in ipairs(search_filter.filtered_files) do
                                            search_filter.sorted_files[i] = file
                                        end
                                        
                                        local col_name = get_column_name_by_index(column_index)
                                        table.sort(search_filter.sorted_files, function(a, b)
                                            local meta_a = cached_metadata[a.full_path] or {}
                                            local meta_b = cached_metadata[b.full_path] or {}
                                            
                                            local val_a, val_b
                                            
                                            if col_name == "name" then
                                                val_a = (a.name or ""):lower()
                                                val_b = (b.name or ""):lower()
                                            elseif col_name == "type" then
                                                val_a = (meta_a.type or ""):lower()
                                                val_b = (meta_b.type or ""):lower()
                                            elseif col_name == "size" then
                                                val_a = meta_a.size_bytes or 0
                                                val_b = meta_b.size_bytes or 0
                                            elseif col_name == "duration" then
                                                val_a = meta_a.duration_seconds or 0
                                                val_b = meta_b.duration_seconds or 0
                                            elseif col_name == "sample_rate" then
                                                val_a = meta_a.sample_rate_hz or 0
                                                val_b = meta_b.sample_rate_hz or 0
                                            elseif col_name == "channels" then
                                                val_a = meta_a.channels_num or 0
                                                val_b = meta_b.channels_num or 0
                                            elseif col_name == "bpm" then
                                                val_a = meta_a.bpm_num or 0
                                                val_b = meta_b.bpm_num or 0
                                            elseif col_name == "key" then
                                                val_a = (meta_a.key or ""):lower()
                                                val_b = (meta_b.key or ""):lower()
                                            elseif col_name == "bitrate" then
                                                val_a = meta_a.bitrate_num or 0
                                                val_b = meta_b.bitrate_num or 0
                                            elseif col_name == "bitspersample" then
                                                val_a = meta_a.bitspersample_num or 0
                                                val_b = meta_b.bitspersample_num or 0
                                            else
                                                val_a = (meta_a[col_name] or ""):lower()
                                                val_b = (meta_b[col_name] or ""):lower()
                                            end
                                            
                                            if val_a ~= val_b then
                                                if sort_direction == r.ImGui_SortDirection_Descending() then
                                                    return val_a > val_b
                                                else
                                                    return val_a < val_b
                                                end
                                            end
                                            
                                            return false
                                        end)
                                    end
                                end
                            end
                        end
                        
                        local files_to_display = (#search_filter.sorted_files > 0) and search_filter.sorted_files or search_filter.filtered_files
                        
                        if ui.scroll_to_top then
                            r.ImGui_SetScrollY(ctx, 0)
                            ui.scroll_to_top = false
                        end
                        
                        if not ui.list_clipper then
                            ui.list_clipper = r.ImGui_CreateListClipper(ctx)
                        end
                        
                        local clipper_valid = ui.list_clipper and r.ImGui_ValidatePtr(ui.list_clipper, 'ImGui_ListClipper*')
                        if not clipper_valid then
                            ui.list_clipper = r.ImGui_CreateListClipper(ctx)
                        end
                        
                        local total_items = #files_to_display
                        r.ImGui_ListClipper_Begin(ui.list_clipper, total_items)
                        
                        while r.ImGui_ListClipper_Step(ui.list_clipper) do
                            local display_start, display_end = r.ImGui_ListClipper_GetDisplayRange(ui.list_clipper)
                            
                            if not display_start or not display_end then
                                break
                            end
                            
                            for i = display_start + 1, display_end do
                                local file = files_to_display[i]
                                if not file then
                                    goto continue
                                end
                                local icon = FILE_ICON
                                
                                local ext = file.ext or string.lower(string.match(file.full_path, "%.([^%.]+)$") or "")
                                local video_exts = {mp4=true, mov=true, avi=true, wmv=true, mkv=true, mpg=true, mpeg=true, flv=true, webm=true, m4v=true}
                                
                                local metadata = cached_metadata[file.full_path]
                                if not metadata then
                                    if video_exts[ext] then
                                        metadata = {
                                            duration = "--",
                                            duration_val = 0,
                                            sample_rate = "--",
                                            sample_rate_val = 0,
                                            channels = "--",
                                            channels_val = 0,
                                            bit_depth = "--",
                                            bit_depth_val = 0,
                                            bitrate = "--",
                                            bitrate_val = 0,
                                            artist = "",
                                            album = "",
                                            date = "",
                                            genre = "",
                                            comment = "",
                                            track_number = "",
                                            track_number_val = 0,
                                            bpm = "--",
                                            bpm_val = 0,
                                            key = "--",
                                            time_signature = "",
                                            composer = "",
                                            publisher = "",
                                            encoded_by = "",
                                            copyright = "",
                                            url = "",
                                            isrc = "",
                                            description = "",
                                            originator = "",
                                            originator_ref = "",
                                            time_reference = "",
                                            time_reference_val = 0,
                                            coding_history = ""
                                        }
                                    else
                                        metadata = get_file_metadata(file.full_path)
                                        cached_metadata[file.full_path] = metadata
                                    end
                                end
                                
                                local display_name = file.name 
                                r.ImGui_TableNextRow(ctx)
                                r.ImGui_TableNextColumn(ctx)
                                
                                local is_multi_selected = is_file_selected(file.full_path)
                                local is_single_selected = file.full_path == playback.current_playing_file
                                
                                if is_single_selected or is_multi_selected then
                                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFFFFFFFF)
                                    ui_settings.pushed_color = 1
                                end
                                
                                if r.ImGui_Selectable(ctx, icon .. " " .. display_name .. "##" .. file.full_path, is_single_selected or is_multi_selected, r.ImGui_SelectableFlags_SpanAllColumns()) then
                                    local ctrl_pressed = r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Ctrl())
                                    local shift_pressed = r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Shift())
                                    
                                    if shift_pressed and file_location.last_selected_index then
                                        select_file_range(file_location.last_selected_index, i, search_filter.filtered_files)
                                    elseif ctrl_pressed then
                                        toggle_file_selection(file.full_path)
                                        file_location.last_selected_index = i
                                    else
                                        clear_file_selection()
                                        
                                        if not playback.auto_play and playback.current_playing_file ~= file.full_path then
                                            if playback.playing_preview or playback.is_midi_playback or playback.is_video_playback then
                                                stop_playback()
                                            end
                                        end
                                        
                                        playback.selected_file = file.name
                                        playback.current_playing_file = file.full_path
                                        file_location.last_selected_index = i
                                        
                                        waveform.selection_active = false
                                        waveform.is_dragging = false
                                        waveform.selection_start = 0
                                        waveform.selection_end = 0
                                        waveform.monitor_sel_start = 0
                                        waveform.monitor_sel_end = 0
                                        waveform.normalized_sel_start = 0
                                        waveform.normalized_sel_end = 0
                                        waveform.monitor_file_path = ""
                                        waveform.play_cursor_position = 0  
                                        
                                        if playback.auto_play then
                                            play_media(file.full_path)
                                        end
                                    end
                                end
                                
                                if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
                                    local track = r.GetSelectedTrack(0, 0)
                                    if track then
                                        if waveform.selection_active and waveform.selection_start ~= waveform.selection_end then
                                            local sel_start = math.min(waveform.selection_start, waveform.selection_end)
                                            local sel_end = math.max(waveform.selection_start, waveform.selection_end)
                                            
                                            local source = r.PCM_Source_CreateFromFile(file.full_path)
                                            if source then
                                                local file_length = r.GetMediaSourceLength(source)
                                                r.PCM_Source_Destroy(source)
                                                
                                                local loop_start_time = sel_start * file_length
                                                local loop_end_time = sel_end * file_length
                                                
                                                local cursor_pos = r.GetCursorPosition()
                                                local item_index = r.GetTrackNumMediaItems(track)
                                                local item = r.AddMediaItemToTrack(track)
                                                r.SetMediaItemPosition(item, cursor_pos, false)
                                                r.SetMediaItemLength(item, loop_end_time - loop_start_time, false)
                                                
                                                local take = r.AddTakeToMediaItem(item)
                                                r.SetMediaItemTake_Source(take, r.PCM_Source_CreateFromFile(file.full_path))
                                                r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", loop_start_time)
                                                
                                                if not playback.use_original_speed then
                                                    r.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", playback.current_playrate)
                                                    r.SetMediaItemTakeInfo_Value(take, "D_PITCH", playback.current_pitch)
                                                    r.SetMediaItemTakeInfo_Value(take, "B_PPITCH", 1)
                                                end
                                                
                                                r.UpdateItemInProject(item)
                                                r.UpdateArrange()
                                            end
                                        else
                                            insert_media_on_track(file.full_path, track, playback.use_original_speed, playback.current_playrate, playback.current_pitch)
                                        end
                                    end
                                end
                                
                                if r.ImGui_BeginPopupContextItem(ctx, "file_context_" .. tostring(i)) then
                                    if #file_location.collections == 0 then
                                        load_collections()
                                    end
                                    
                                    local files_to_process = {}
                                    if #file_location.selected_files > 0 then
                                        files_to_process = file_location.selected_files
                                    else
                                        table.insert(files_to_process, file.full_path)
                                    end
                                    
                                    if #file_location.selected_files > 0 then
                                        r.ImGui_Text(ctx, string.format("%d files selected", #file_location.selected_files))
                                        r.ImGui_Separator(ctx)
                                    end
                                    
                                    if ui.current_view_mode == "collections" and file_location.selected_collection then
                                        local remove_label = #file_location.selected_files > 0 
                                            and string.format("Remove %d files from Collection", #file_location.selected_files)
                                            or "Remove from Collection"
                                        
                                        if r.ImGui_MenuItem(ctx, remove_label) then
                                            remove_file_from_collection(file_location.selected_collection, i)
                                            clear_sort_cache()  
                                            local db_data = load_collection(file_location.selected_collection)
                                            if db_data and db_data.items then
                                                file_location.current_files = {}
                                                search_filter.cached_flat_files = {}
                                                for _, item in ipairs(db_data.items) do
                                                    local file_entry = {
                                                        name = item.path:match("([^/\\]+)$"),
                                                        full_path = item.path,
                                                        is_dir = false
                                                    }
                                                    table.insert(file_location.current_files, file_entry)
                                                    table.insert(search_filter.cached_flat_files, file_entry)
                                                end
                                                search_filter.filtered_files = search_filter.cached_flat_files
                                            end
                                            clear_file_selection()
                                        end
                                        r.ImGui_Separator(ctx)
                                    end
                                    
                                    local ext = file.full_path:match("%.([^%.]+)$")
                                    if ext then
                                        ext = ext:lower()
                                        if ext ~= "mid" and ext ~= "midi" then
                                            if r.ImGui_MenuItem(ctx, "Add to new track with ReaSamplomatic5000") then
                                                insert_with_reasamplomatic(file.full_path)
                                            end
                                            if r.ImGui_MenuItem(ctx, "Replace or add sample on selected track") then
                                                replace_reasamplomatic_sample(file.full_path)
                                            end
                                            r.ImGui_Separator(ctx)
                                        end
                                    end
                                    
                                    r.ImGui_Text(ctx, "Add to Collection:")
                                    r.ImGui_Separator(ctx)
                                    
                                    if #file_location.collections > 0 then
                                        for _, db_name in ipairs(file_location.collections) do
                                            local db = load_collection(db_name)
                                            if db and db.categories and #db.categories > 0 then
                                                if r.ImGui_BeginMenu(ctx, db_name .. " >>") then
                                                    if r.ImGui_MenuItem(ctx, "No Category") then
                                                        if #files_to_process > 1 then
                                                            add_multiple_files_to_collection(db_name, files_to_process, nil)
                                                            clear_file_selection()
                                                        else
                                                            add_file_to_collection(db_name, file.full_path, nil)
                                                        end
                                                    end
                                                    r.ImGui_Separator(ctx)
                                                    for _, cat in ipairs(db.categories) do
                                                        if r.ImGui_MenuItem(ctx, cat) then
                                                            if #files_to_process > 1 then
                                                                add_multiple_files_to_collection(db_name, files_to_process, {cat})
                                                                clear_file_selection()
                                                            else
                                                                add_file_to_collection(db_name, file.full_path, {cat})
                                                            end
                                                        end
                                                    end
                                                    r.ImGui_EndMenu(ctx)
                                                end
                                            else
                                                if r.ImGui_MenuItem(ctx, db_name) then
                                                    if #files_to_process > 1 then
                                                        add_multiple_files_to_collection(db_name, files_to_process, nil)
                                                        clear_file_selection()
                                                    else
                                                        add_file_to_collection(db_name, file.full_path, nil)
                                                    end
                                                end
                                            end
                                        end
                                        r.ImGui_Separator(ctx)
                                    end
                                    
                                    if r.ImGui_MenuItem(ctx, "+ New Collection...") then
                                        local retval, new_db_name = r.GetUserInputs("New Collection", 1, "Collection Name:", "")
                                        if retval and new_db_name ~= "" then
                                            create_new_collection(new_db_name)
                                            if #files_to_process > 1 then
                                                add_multiple_files_to_collection(new_db_name, files_to_process)
                                                clear_file_selection()
                                            else
                                                add_file_to_collection(new_db_name, file.full_path)
                                            end
                                            load_collections()
                                        end
                                    end
                                    
                                    r.ImGui_EndPopup(ctx)
                                end
                                
                                if ui_settings.pushed_color > 0 then
                                    r.ImGui_PopStyleColor(ctx, ui_settings.pushed_color)
                                    ui_settings.pushed_color = 0
                                end
                                handle_drag_drop(file.full_path)
                                if ui_settings.visible_columns.type then
                                    r.ImGui_TableNextColumn(ctx)
                                    r.ImGui_Text(ctx, metadata.type)
                                end
                                if ui_settings.visible_columns.size then
                                    r.ImGui_TableNextColumn(ctx)
                                    r.ImGui_Text(ctx, metadata.size)
                                end
                                if ui_settings.visible_columns.duration then
                                    r.ImGui_TableNextColumn(ctx)
                                    r.ImGui_Text(ctx, metadata.duration)
                                end
                                if ui_settings.visible_columns.sample_rate then
                                    r.ImGui_TableNextColumn(ctx)
                                    r.ImGui_Text(ctx, metadata.sample_rate)
                                end
                                if ui_settings.visible_columns.channels then
                                    r.ImGui_TableNextColumn(ctx)
                                    r.ImGui_Text(ctx, metadata.channels)
                                end
                                if ui_settings.visible_columns.bpm then
                                    r.ImGui_TableNextColumn(ctx)
                                    r.ImGui_Text(ctx, metadata.bpm)
                                end
                                if ui_settings.visible_columns.key then
                                    r.ImGui_TableNextColumn(ctx)
                                    r.ImGui_Text(ctx, metadata.key)
                                end
                                if ui_settings.visible_columns.artist then
                                    r.ImGui_TableNextColumn(ctx)
                                    r.ImGui_Text(ctx, metadata.artist)
                                end
                                if ui_settings.visible_columns.album then
                                    r.ImGui_TableNextColumn(ctx)
                                    r.ImGui_Text(ctx, metadata.album)
                                end
                                if ui_settings.visible_columns.title then
                                    r.ImGui_TableNextColumn(ctx)
                                    r.ImGui_Text(ctx, metadata.title)
                                end
                                if ui_settings.visible_columns.track then
                                    r.ImGui_TableNextColumn(ctx)
                                    r.ImGui_Text(ctx, metadata.track)
                                end
                                if ui_settings.visible_columns.year then
                                    r.ImGui_TableNextColumn(ctx)
                                    r.ImGui_Text(ctx, metadata.year)
                                end
                                if ui_settings.visible_columns.genre then
                                    r.ImGui_TableNextColumn(ctx)
                                    r.ImGui_Text(ctx, metadata.genre)
                                end
                                if ui_settings.visible_columns.comment then
                                    r.ImGui_TableNextColumn(ctx)
                                    r.ImGui_Text(ctx, metadata.comment)
                                end
                                if ui_settings.visible_columns.composer then
                                    r.ImGui_TableNextColumn(ctx)
                                    r.ImGui_Text(ctx, metadata.composer)
                                end
                                if ui_settings.visible_columns.publisher then
                                    r.ImGui_TableNextColumn(ctx)
                                    r.ImGui_Text(ctx, metadata.publisher)
                                end
                                if ui_settings.visible_columns.timesignature then
                                    r.ImGui_TableNextColumn(ctx)
                                    r.ImGui_Text(ctx, metadata.timesignature)
                                end
                                if ui_settings.visible_columns.bitrate then
                                    r.ImGui_TableNextColumn(ctx)
                                    r.ImGui_Text(ctx, metadata.bitrate)
                                end
                                if ui_settings.visible_columns.bitspersample then
                                    r.ImGui_TableNextColumn(ctx)
                                    r.ImGui_Text(ctx, metadata.bitspersample)
                                end
                                if ui_settings.visible_columns.encoder then
                                    r.ImGui_TableNextColumn(ctx)
                                    r.ImGui_Text(ctx, metadata.encoder)
                                end
                                if ui_settings.visible_columns.copyright then
                                    r.ImGui_TableNextColumn(ctx)
                                    r.ImGui_Text(ctx, metadata.copyright)
                                end
                                if ui_settings.visible_columns.desc then
                                    r.ImGui_TableNextColumn(ctx)
                                    r.ImGui_Text(ctx, metadata.desc)
                                end
                                if ui_settings.visible_columns.originator then
                                    r.ImGui_TableNextColumn(ctx)
                                    r.ImGui_Text(ctx, metadata.originator)
                                end
                                if ui_settings.visible_columns.originatorref then
                                    r.ImGui_TableNextColumn(ctx)
                                    r.ImGui_Text(ctx, metadata.originatorref)
                                end
                                if ui_settings.visible_columns.date then
                                    r.ImGui_TableNextColumn(ctx)
                                    r.ImGui_Text(ctx, metadata.date)
                                end
                                if ui_settings.visible_columns.time then
                                    r.ImGui_TableNextColumn(ctx)
                                    r.ImGui_Text(ctx, metadata.time)
                                end
                                if ui_settings.visible_columns.umid then
                                    r.ImGui_TableNextColumn(ctx)
                                    r.ImGui_Text(ctx, metadata.umid)
                                end
                                ::continue::
                            end
                        end
                        
                        r.ImGui_ListClipper_End(ui.list_clipper)
                        
                        r.ImGui_EndTable(ctx)
                        r.ImGui_PopStyleVar(ctx, 1)  
                        r.ImGui_PopStyleColor(ctx, 6)  
                    end
                else
                    local accent_color = hsv_to_color(ui_settings.accent_hue, 1.0, 1.0, 0.4)  
                    local accent_hover_color = hsv_to_color(ui_settings.accent_hue, 0.8, 1.0, 0.3)  
                    local accent_active_color = hsv_to_color(ui_settings.accent_hue, 1.0, 0.8, 0.5)  

                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), accent_color)
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), accent_hover_color)
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), accent_active_color)
                    
                    display_tree(file_location.current_files, file_location.current_location)
                    
                    r.ImGui_PopStyleColor(ctx, 3)  
                end
                
                r.ImGui_EndChild(ctx)
            end
            r.ImGui_PopStyleVar(ctx, 2) 
        end
end
local function draw_file_info()
    if playback.current_playing_file ~= "" and not playback.current_playing_file:match("%.midi?$") then
        local info = get_audio_file_info(playback.current_playing_file)
        if info then
            r.ImGui_Separator(ctx)
            local file_name = playback.current_playing_file:match("([^/\\]+)$")
            r.ImGui_Text(ctx, "Selected file:")
            r.ImGui_TextWrapped(ctx, file_name)
            r.ImGui_Separator(ctx)
            r.ImGui_Text(ctx, "Sample rate: " .. info.sample_rate .. " Hz")
            r.ImGui_Text(ctx, "Channels: " .. info.num_channels)
            r.ImGui_Text(ctx, "Length: " .. string.format("%.2f", info.length) .. " seconds")
            r.ImGui_Dummy(ctx, 0, 20)
        end
    else
        r.ImGui_Text(ctx, "Select a file")
        r.ImGui_TextWrapped(ctx, "Click on a file in the list to see details")
    end
end
local function calculate_window_height()
    local min_height = 500
    if not show_browser_section then
        min_height = 200
    end
    return min_height
end

local function draw_category_manager()
    if not file_location.show_category_manager then return end
    
    r.ImGui_SetNextWindowSize(ctx, 400, 300, r.ImGui_Cond_FirstUseEver())
    local visible, open = r.ImGui_Begin(ctx, "Category Manager##catmanager", true)
    file_location.show_category_manager = open
    
    if visible then
        if not file_location.selected_collection then
            r.ImGui_TextWrapped(ctx, "Please select a collection first.")
            r.ImGui_End(ctx)
            return
        end
        
        local db = load_collection(file_location.selected_collection)
        if not db then
            r.ImGui_TextWrapped(ctx, "Failed to load collection.")
            r.ImGui_End(ctx)
            return
        end
        
        r.ImGui_SeparatorText(ctx, "Categories for: " .. file_location.selected_collection)
        
        db.categories = db.categories or {}
        if #db.categories == 0 then
            r.ImGui_TextWrapped(ctx, "No categories yet. Add one below.")
        else
            r.ImGui_BeginChild(ctx, "CategoryList", 0, -60)
            for i, category in ipairs(db.categories) do
                r.ImGui_Text(ctx, category)
                r.ImGui_SameLine(ctx)
                r.ImGui_PushID(ctx, "del_" .. i)
                if r.ImGui_Button(ctx, "Remove") then
                    remove_category_from_collection(file_location.selected_collection, category)
                    
                    local items = get_collection_items_by_category(file_location.selected_collection, file_location.selected_category)
                    file_location.current_files = {}
                    search_filter.cached_flat_files = {}
                    for _, item in ipairs(items) do
                        local file_entry = {
                            name = item.path:match("([^/\\]+)$"),
                            full_path = item.path,
                            is_dir = false
                        }
                        table.insert(file_location.current_files, file_entry)
                        table.insert(search_filter.cached_flat_files, file_entry)
                    end
                    search_filter.filtered_files = search_filter.cached_flat_files
                end
                r.ImGui_PopID(ctx)
            end
            r.ImGui_EndChild(ctx)
        end
        
        r.ImGui_Separator(ctx)
        r.ImGui_Text(ctx, "Add New Category:")
        local changed, new_text = r.ImGui_InputText(ctx, "##newcat", file_location.new_category_name)
        if changed then file_location.new_category_name = new_text end
        
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Add") and file_location.new_category_name ~= "" then
            if add_category_to_collection(file_location.selected_collection, file_location.new_category_name) then
                file_location.new_category_name = ""
            end
        end
        
        r.ImGui_End(ctx)
    end
end

local function draw_rename_folder_popup()
    if not file_location.rename_popup_location then return end
    if file_location.renaming_location ~= nil then
        file_location.rename_popup_location = nil
        file_location.rename_popup_initialized = false
        return
    end
    
    if not file_location.rename_popup_initialized then
        ui_settings.new_name = ""
        ui_settings.last_nonempty_new_name = nil
        r.ImGui_OpenPopup(ctx, "Rename Folder##renamefolder")
        file_location.rename_popup_initialized = true
    end
    
    r.ImGui_SetNextWindowSize(ctx, 400, 140, r.ImGui_Cond_Always())
    local visible, is_open = r.ImGui_BeginPopupModal(ctx, "Rename Folder##renamefolder", true, r.ImGui_WindowFlags_NoResize())
    
    if visible then
        local location = file_location.rename_popup_location
        local original_name = location:match("([^/\\]+)[/\\]?$") or location
        
    r.ImGui_Text(ctx, "Enter new display name:")
    r.ImGui_Text(ctx, "Original: " .. original_name)
        r.ImGui_Spacing(ctx)
        
        if r.ImGui_IsWindowAppearing(ctx) then
            r.ImGui_SetKeyboardFocusHere(ctx)
        end
        local submit_pressed, new_text = r.ImGui_InputText(ctx, "##renameinput", ui_settings.new_name, r.ImGui_InputTextFlags_EnterReturnsTrue())
        ui_settings.new_name = new_text
        if new_text ~= nil and new_text ~= "" then
            ui_settings.last_nonempty_new_name = new_text
        end
        
        r.ImGui_Spacing(ctx)
        
    local effective_text = (ui_settings.new_name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local ok_disabled = (effective_text == "")
    if ok_disabled then r.ImGui_BeginDisabled(ctx, true) end
    local ok_clicked = r.ImGui_Button(ctx, "OK", 120, 0)
    if ok_disabled then r.ImGui_EndDisabled(ctx) end
        r.ImGui_SameLine(ctx)
        local cancel_clicked = r.ImGui_Button(ctx, "Cancel", 120, 0)
        
        local do_commit = ok_clicked or submit_pressed
        local do_cancel = cancel_clicked
        if do_commit or do_cancel then
            r.ImGui_CloseCurrentPopup(ctx)
        end
        
        r.ImGui_EndPopup(ctx)
        
        if do_commit then
            local current = ui_settings.new_name or ""
            local trimmed = current:gsub("^%s+", ""):gsub("%s+$", "")
            if trimmed == "" then
                local fallback = (ui_settings.last_nonempty_new_name or ""):gsub("^%s+", ""):gsub("%s+$", "")
                trimmed = fallback
            end
            if trimmed == "" then
                file_location.custom_folder_names[location] = nil
            else
                file_location.custom_folder_names[location] = trimmed
            end
            save_options()
            ui_settings.new_name = ""
            ui_settings.last_nonempty_new_name = nil
            file_location.rename_popup_location = nil
            file_location.rename_popup_initialized = false
        elseif do_cancel then
            ui_settings.new_name = ""
            ui_settings.last_nonempty_new_name = nil
            file_location.rename_popup_location = nil
            file_location.rename_popup_initialized = false
        end
        
        if not is_open then
            ui_settings.new_name = ""
            ui_settings.last_nonempty_new_name = nil
            file_location.rename_popup_location = nil
            file_location.rename_popup_initialized = false
        end
    else
        if not is_open then
            ui_settings.new_name = ""
            ui_settings.last_nonempty_new_name = nil
            file_location.rename_popup_location = nil
            file_location.rename_popup_initialized = false
        end
    end
end

local function handle_keyboard_navigation()
    local is_any_item_active = r.ImGui_IsAnyItemActive(ctx)
    local is_any_popup_open = r.ImGui_IsPopupOpen(ctx, '', r.ImGui_PopupFlags_AnyPopupId())
    
    if is_any_item_active or is_any_popup_open then
        return false
    end
    
    local key_up = r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_UpArrow())
    local key_down = r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_DownArrow())
    local key_enter = r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Enter())
    local key_page_up = r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_PageUp())
    local key_page_down = r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_PageDown())
    local key_home = r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Home())
    local key_end = r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_End())
    if #ui.visible_files > 0 then
        if key_up and ui.selected_index > 1 then
            ui.selected_index = ui.selected_index - 1
            playback.selected_file = ui.visible_files[ui.selected_index].name
            
            waveform.selection_active = false
            waveform.is_dragging = false
            waveform.selection_start = 0
            waveform.selection_end = 0
            waveform.monitor_sel_start = 0
            waveform.monitor_sel_end = 0
            waveform.normalized_sel_start = 0
            waveform.normalized_sel_end = 0
            waveform.monitor_file_path = ""
            waveform.play_cursor_position = 0
            
            local file_path = ui.visible_files[ui.selected_index].full_path or ui.visible_files[ui.selected_index].path
            
            if not playback.auto_play and playback.current_playing_file ~= file_path then
                if playback.playing_preview or playback.is_midi_playback or playback.is_video_playback then
                    stop_playback()
                end
            end
            
            playback.current_playing_file = file_path
            
            if playback.auto_play then
                play_media(file_path)
            end
            return true
        elseif key_down and ui.selected_index < #ui.visible_files then
            ui.selected_index = ui.selected_index + 1
            playback.selected_file = ui.visible_files[ui.selected_index].name
            
            waveform.selection_active = false
            waveform.is_dragging = false
            waveform.selection_start = 0
            waveform.selection_end = 0
            waveform.monitor_sel_start = 0
            waveform.monitor_sel_end = 0
            waveform.normalized_sel_start = 0
            waveform.normalized_sel_end = 0
            waveform.monitor_file_path = ""
            waveform.play_cursor_position = 0
            
            local file_path = ui.visible_files[ui.selected_index].full_path or ui.visible_files[ui.selected_index].path
            
            if not playback.auto_play and playback.current_playing_file ~= file_path then
                if playback.playing_preview or playback.is_midi_playback or playback.is_video_playback then
                    stop_playback()
                end
            end
            
            playback.current_playing_file = file_path
            
            if playback.auto_play then
                play_media(file_path)
            end
            return true
        elseif key_page_up then
            local new_index = math.max(1, ui.selected_index - 10)
            if new_index ~= ui.selected_index then
                ui.selected_index = new_index
                playback.selected_file = ui.visible_files[ui.selected_index].name
                
                waveform.selection_active = false
                waveform.is_dragging = false
                waveform.selection_start = 0
                waveform.selection_end = 0
                waveform.monitor_sel_start = 0
                waveform.monitor_sel_end = 0
                waveform.normalized_sel_start = 0
                waveform.normalized_sel_end = 0
                waveform.monitor_file_path = ""
                waveform.play_cursor_position = 0
                
                local file_path = ui.visible_files[ui.selected_index].full_path or ui.visible_files[ui.selected_index].path
                
                if not playback.auto_play and playback.current_playing_file ~= file_path then
                    if playback.playing_preview or playback.is_midi_playback or playback.is_video_playback then
                        stop_playback()
                    end
                end
                
                playback.current_playing_file = file_path
                if playback.auto_play then
                    play_media(file_path)
                end
            end
            return true
        elseif key_page_down then
            local new_index = math.min(#ui.visible_files, ui.selected_index + 10)
            if new_index ~= ui.selected_index then
                ui.selected_index = new_index
                playback.selected_file = ui.visible_files[ui.selected_index].name
                
                waveform.selection_active = false
                waveform.is_dragging = false
                waveform.selection_start = 0
                waveform.selection_end = 0
                waveform.monitor_sel_start = 0
                waveform.monitor_sel_end = 0
                waveform.normalized_sel_start = 0
                waveform.normalized_sel_end = 0
                waveform.monitor_file_path = ""
                waveform.play_cursor_position = 0
                
                local file_path = ui.visible_files[ui.selected_index].full_path or ui.visible_files[ui.selected_index].path
                
                if not playback.auto_play and playback.current_playing_file ~= file_path then
                    if playback.playing_preview or playback.is_midi_playback or playback.is_video_playback then
                        stop_playback()
                    end
                end
                
                playback.current_playing_file = file_path
                if playback.auto_play then
                    play_media(file_path)
                end
            end
            return true
        elseif key_home then
            if #ui.visible_files > 0 then
                ui.selected_index = 1
                playback.selected_file = ui.visible_files[ui.selected_index].name
                
                waveform.selection_active = false
                waveform.is_dragging = false
                waveform.selection_start = 0
                waveform.selection_end = 0
                waveform.monitor_sel_start = 0
                waveform.monitor_sel_end = 0
                waveform.normalized_sel_start = 0
                waveform.normalized_sel_end = 0
                waveform.monitor_file_path = ""
                waveform.play_cursor_position = 0
                
                local file_path = ui.visible_files[ui.selected_index].full_path or ui.visible_files[ui.selected_index].path
                
                if not playback.auto_play and playback.current_playing_file ~= file_path then
                    if playback.playing_preview or playback.is_midi_playback or playback.is_video_playback then
                        stop_playback()
                    end
                end
                
                playback.current_playing_file = file_path
                if playback.auto_play then
                    play_media(file_path)
                end
            end
            return true
        elseif key_end then
            if #ui.visible_files > 0 then
                ui.selected_index = #ui.visible_files
                playback.selected_file = ui.visible_files[ui.selected_index].name
                
                waveform.selection_active = false
                waveform.is_dragging = false
                waveform.selection_start = 0
                waveform.selection_end = 0
                waveform.monitor_sel_start = 0
                waveform.monitor_sel_end = 0
                waveform.normalized_sel_start = 0
                waveform.normalized_sel_end = 0
                waveform.monitor_file_path = ""
                waveform.play_cursor_position = 0
                
                local file_path = ui.visible_files[ui.selected_index].full_path or ui.visible_files[ui.selected_index].path
                
                if not playback.auto_play and playback.current_playing_file ~= file_path then
                    if playback.playing_preview or playback.is_midi_playback or playback.is_video_playback then
                        stop_playback()
                    end
                end
                
                playback.current_playing_file = file_path
                if playback.auto_play then
                    play_media(file_path)
                end
            end
            return true
        elseif key_enter and ui.selected_index >= 1 and ui.selected_index <= #ui.visible_files then
            local file_path = ui.visible_files[ui.selected_index].full_path or ui.visible_files[ui.selected_index].path
            if playback.current_playing_file == file_path and Play then
                stop_playback(false)
            else
                playback.current_playing_file = file_path
                play_media(file_path)
            end
            return true
        end
    end
    return false
end
local function draw_progress_window()
    if not cache_mgmt.show_progress then
        return
    end
    
    local window_flags = r.ImGui_WindowFlags_NoCollapse() | 
                        r.ImGui_WindowFlags_NoResize() |
                        r.ImGui_WindowFlags_AlwaysAutoResize() |
                        r.ImGui_WindowFlags_NoScrollbar()
    
    r.ImGui_SetNextWindowSize(ctx, 400, 0)
    
    local viewport = r.ImGui_GetWindowViewport(ctx)
    local center_x, center_y = r.ImGui_Viewport_GetCenter(viewport)
    r.ImGui_SetNextWindowPos(ctx, center_x, center_y, r.ImGui_Cond_Appearing(), 0.5, 0.5)
    
    local visible, open = r.ImGui_Begin(ctx, "Scanning Files...", true, window_flags)
    if visible then
        r.ImGui_Text(ctx, "Building file cache and loading metadata...")
        r.ImGui_Spacing(ctx)
        
        local total = cache_mgmt.total_files > 0 and cache_mgmt.total_files or 1
        local progress = cache_mgmt.processed_files / total
        
        r.ImGui_ProgressBar(ctx, progress, -1, 0, 
            string.format("%d / %d files", cache_mgmt.processed_files, cache_mgmt.total_files))
        
        r.ImGui_Spacing(ctx)
        
        local fun_messages = {
            "Time to grab a coffee...",
            "Perfect moment for a bathroom break!",
            "Why not check your phone?",
            "Great time to stretch those legs!",
            "Maybe organize your desktop?",
            "Dream about that vacation...",
            "Practice your air guitar!",
            "Count the ceiling tiles...",
            "Contemplate life's mysteries...",
            "Do some desk push-ups!"
        }
        
        if cache_mgmt.total_files > 10000 then
            local message_index = ((cache_mgmt.total_files // 1000) % #fun_messages) + 1
            r.ImGui_TextWrapped(ctx, fun_messages[message_index])
            r.ImGui_Spacing(ctx)
        end
        
        r.ImGui_TextWrapped(ctx, "This only happens once per folder. Subsequent loads will be instant.")
        
        r.ImGui_End(ctx)
    end
    
    if not open then
        cache_mgmt.show_progress = false
    end
end

local function loop()
    if not file_location.collection_restored and ui.current_view_mode == "collections" and file_location.last_collection_name then
        load_collections()
        file_location.selected_collection = file_location.last_collection_name
        clear_sort_cache() 
        local db_data = load_collection(file_location.last_collection_name)
        if db_data and db_data.items then
            file_location.current_files = {}
            search_filter.cached_flat_files = {}
            for _, item in ipairs(db_data.items) do
                local file_entry = {
                    name = item.path:match("([^/\\]+)$"),
                    full_path = item.path,
                    is_dir = false
                }
                table.insert(file_location.current_files, file_entry)
                table.insert(search_filter.cached_flat_files, file_entry)
            end
            file_location.current_location = "Collection: " .. file_location.last_collection_name
            search_filter.cached_location = file_location.current_location
            search_filter.filtered_files = search_filter.cached_flat_files
            file_location.flat_view = true
            
        end
        file_location.collection_restored = true
    end
    
    if not r.ImGui_ValidatePtr(ctx, 'ImGui_Context*') then
        ctx = r.ImGui_CreateContext('TK Media Browser')
        normal_font = r.ImGui_CreateFont('sans-serif', font_size)
        r.ImGui_Attach(ctx, normal_font)
    end
    local video_open = is_video_window_open()
    if not playback.speed_manually_changed and playback.use_original_speed ~= video_open then
        playback.use_original_speed = video_open
        save_options()
    end
    
    sync_transport_with_preview()
    
    r.ImGui_PushFont(ctx, normal_font, font_size)
    reaper.ImGui_SetNextWindowBgAlpha(ctx, 0.9)
    local window_height = calculate_window_height()
    reaper.ImGui_SetNextWindowSizeConstraints(ctx, 140, window_height, 16384, window_height)
    if file_location.current_files and #file_location.current_files > 0 then
        if file_location.flat_view then
            ui.visible_files = {}
            local files_to_use = (search_filter.filtered_files and #search_filter.filtered_files > 0) and search_filter.filtered_files or search_filter.cached_flat_files
            for i = 1, #files_to_use do
                local file = files_to_use[i]
                if file and not file.is_dir then
                    table.insert(ui.visible_files, {
                        name = file.name,
                        path = file.full_path,
                        full_path = file.full_path,
                        parent_folder = file.parent_folder
                    })
                end
            end
        else
            ui.visible_files = build_visible_files_list(file_location.current_files, file_location.current_location)
        end
        local found = false
        for i, file in ipairs(ui.visible_files) do
            if file.name == playback.selected_file then
                ui.selected_index = i
                found = true
                break
            end
        end
        if not found and #ui.visible_files > 0 then
            ui.selected_index = 1
            playback.selected_file = ui.visible_files[1].name
        end
    end
    local sync_reference_path = get_reference_file_path()
    if playback.pending_sync_refresh then
        if not refresh_effective_playrate(sync_reference_path) then
            playback.pending_sync_refresh = true
        end
    elseif not playback.use_original_speed then
        if sync_reference_path and sync_reference_path ~= playback.last_sync_reference then
            refresh_effective_playrate(sync_reference_path)
        end
    elseif playback.use_original_speed and playback.last_sync_reference then
        playback.last_sync_reference = nil
    end
    if ui.remember_window_position and not ui.position_applied then
        r.ImGui_SetNextWindowPos(ctx, ui.window_x, ui.window_y, r.ImGui_Cond_FirstUseEver())
        ui.position_applied = true
    end
    r.ImGui_SetNextWindowSizeConstraints(ctx, 650, 400, 9999, 9999)
    r.ImGui_SetNextWindowSize(ctx, 650, 400, r.ImGui_Cond_FirstUseEver())
    
    r.ImGui_SetNextWindowBgAlpha(ctx, ui_settings.window_opacity)
    
    local window_bg_color = r.ImGui_ColorConvertDouble4ToU32(
        ui_settings.window_bg_brightness,
        ui_settings.window_bg_brightness,
        ui_settings.window_bg_brightness,
        ui_settings.window_opacity
    )
    
    local child_bg_color = r.ImGui_ColorConvertDouble4ToU32(
        ui_settings.window_bg_brightness,
        ui_settings.window_bg_brightness,
        ui_settings.window_bg_brightness,
        0.0
    )
    
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 8)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), window_bg_color)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), child_bg_color)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), window_bg_color)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), r.ImGui_ColorConvertDouble4ToU32(
        ui_settings.text_brightness,
        ui_settings.text_brightness,
        ui_settings.text_brightness,
        1.0
    ))
    
    local visible, open = r.ImGui_Begin(ctx, 'TK Media Browser', true,
    r.ImGui_WindowFlags_NoTitleBar())
    
    if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape()) then
        open = false
    end
    if visible and not r.ImGui_IsPopupOpen(ctx, '', r.ImGui_PopupFlags_AnyPopupId()) then
        handle_keyboard_navigation()
    end
    if r.ImGui_IsWindowDocked(ctx) then
        local current_width = r.ImGui_GetWindowWidth(ctx)
        r.ImGui_SetWindowSize(ctx, current_width, calculate_window_height())
    end
    if ui.remember_window_position and not r.ImGui_IsWindowDocked(ctx) then
        local new_x, new_y = r.ImGui_GetWindowPos(ctx)
        if math.abs(new_x - ui.window_x) > 1 or math.abs(new_y - ui.window_y) > 1 then
            ui.window_x = new_x
            ui.window_y = new_y
            local current_time = r.time_precise()
            if current_time - ui.last_move_time > 0.5 then
                save_options()
                ui.last_move_time = current_time
            end
        end
    end
    if visible then
        local left_panel_width = 200
        local window_width = r.ImGui_GetContentRegionAvail(ctx)
        local right_panel_width = math.max(200, window_width - left_panel_width - 10)
        if r.ImGui_BeginChild(ctx, "LeftControlPanel", left_panel_width, 0, r.ImGui_WindowFlags_None()) then
            local LEFT_FOOTER_H = ui.show_oscilloscope and 228 or 100  
            local LEFT_HEADER_H = 0  
            local header_button_width = (left_panel_width - 6) / 2 
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 3)
            
            local button_color = r.ImGui_ColorConvertDouble4ToU32(ui_settings.button_brightness, ui_settings.button_brightness, ui_settings.button_brightness, 1.0)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), button_color)
            
            local accent_color = hsv_to_color(ui_settings.accent_hue, 1.0, 1.0)
            local accent_hover_color = hsv_to_color(ui_settings.accent_hue, 0.8, 1.0)  
            local accent_active_color = hsv_to_color(ui_settings.accent_hue, 1.0, 0.8)  
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), accent_hover_color)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), accent_active_color)
            
            local button_text_color = r.ImGui_ColorConvertDouble4ToU32(ui_settings.button_text_brightness, ui_settings.button_text_brightness, ui_settings.button_text_brightness, 1.0)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), button_text_color)
            
            if ui.current_view_mode == "folders" then
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), accent_color)
                ui_settings.pushed_color = 1
            end
            if r.ImGui_Button(ctx, "Folders", header_button_width, LEFT_HEADER_H) then
                if ui.current_view_mode == "collections" and file_location.selected_collection then
                    file_location.last_collection_name = file_location.selected_collection
                end
                
                clear_sort_cache()  
                ui.current_view_mode = "folders"
                ui.show_collection_section = false
                clear_file_selection()
                file_location.flat_view = file_location.saved_folder_flat_view
                
                
                if file_location.last_folder_location ~= "" and file_location.last_folder_index > 0 then
                    file_location.selected_location_index = file_location.last_folder_index
                    file_location.current_location = file_location.last_folder_location
                    file_location.current_files = read_directory_recursive(file_location.current_location, false)
                end
                
                save_options()
            end
            if ui_settings.pushed_color > 0 then
                r.ImGui_PopStyleColor(ctx, 1)
                ui_settings.pushed_color = 0
            end
            
            r.ImGui_SameLine(ctx, 0, 2)
            
            if ui.current_view_mode == "collections" then
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), accent_color)
                ui_settings.pushed_color = 1
            end
            if r.ImGui_Button(ctx, "collections", header_button_width, LEFT_HEADER_H) then
                if ui.current_view_mode == "folders" and file_location.current_location ~= "" then
                    file_location.last_folder_location = file_location.current_location
                    file_location.last_folder_index = file_location.selected_location_index
                    file_location.saved_folder_flat_view = file_location.flat_view  
                end
                
                clear_sort_cache()  
                ui.current_view_mode = "collections"
                ui.show_collection_section = true
                clear_file_selection()
                load_collections()
                
                if file_location.last_collection_name then
                    file_location.selected_collection = file_location.last_collection_name
                    local db_data = load_collection(file_location.last_collection_name)
                    if db_data then
                        local items = get_collection_items_by_category(file_location.last_collection_name, file_location.selected_category)
                        file_location.current_files = {}
                        search_filter.cached_flat_files = {}
                        for _, item in ipairs(items) do
                            local file_entry = {
                                name = item.path:match("([^/\\]+)$"),
                                full_path = item.path,
                                is_dir = false
                            }
                            table.insert(file_location.current_files, file_entry)
                            table.insert(search_filter.cached_flat_files, file_entry)
                        end
                        file_location.current_location = "Collection: " .. file_location.last_collection_name
                        search_filter.cached_location = file_location.current_location
                        search_filter.filtered_files = search_filter.cached_flat_files
                        file_location.flat_view = true
                        
                    end
                end
                
                save_options()
            end
            if ui_settings.pushed_color > 0 then
                r.ImGui_PopStyleColor(ctx, 1)
                ui_settings.pushed_color = 0
            end
            
            r.ImGui_PopStyleColor(ctx, 4)  
            r.ImGui_PopStyleVar(ctx, 1)
            r.ImGui_Separator(ctx)
            
            if ui_settings.hide_scrollbar then
                r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ScrollbarSize(), 0)
            end
            
            if r.ImGui_BeginChild(ctx, "LeftPanelContent", 0, -LEFT_FOOTER_H) then
        
        if ui.current_view_mode == "folders" then
            local total_width = reaper.ImGui_GetContentRegionAvail(ctx)
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 3)
            
            local unselected_button_color = r.ImGui_ColorConvertDouble4ToU32(ui_settings.button_brightness, ui_settings.button_brightness, ui_settings.button_brightness, 1.0)
            local button_text_color = r.ImGui_ColorConvertDouble4ToU32(ui_settings.button_text_brightness, ui_settings.button_text_brightness, ui_settings.button_text_brightness, 1.0)
            local accent_color = hsv_to_color(ui_settings.accent_hue, 1.0, 1.0)
            local accent_hover_color = hsv_to_color(ui_settings.accent_hue, 0.8, 1.0)
            local accent_active_color = hsv_to_color(ui_settings.accent_hue, 1.0, 0.8)
            
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), accent_hover_color)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), accent_active_color)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), button_text_color)
            
            for i, location in ipairs(file_location.locations) do
                local is_selected = (i == file_location.selected_location_index)
                local folder_name = file_location.custom_folder_names[location] or (location:match("([^/\\]+)[/\\]?$") or location)
                
                local base_color
                if is_selected then
                    base_color = accent_color
                elseif file_location.custom_folder_colors[location] then
                    local c = file_location.custom_folder_colors[location]
                    base_color = hsv_to_color(c.h, c.s, c.v)
                else
                    base_color = unselected_button_color
                end
                
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), base_color)
                
                local is_renaming = (file_location.renaming_location == location)
                if is_renaming then
                    if not file_location.renaming_initialized then
                        local original_name = location:match("([^/\\]+)[/\\]?$") or location
                        ui_settings.rename_inline_text = file_location.custom_folder_names[location] or original_name
                        file_location.renaming_initialized = true
                    end
                    r.ImGui_PushItemWidth(ctx, total_width - 260)
                    local enter_pressed, new_inline = r.ImGui_InputText(ctx, "##inline_rename_" .. i, ui_settings.rename_inline_text, r.ImGui_InputTextFlags_EnterReturnsTrue())
                    ui_settings.rename_inline_text = new_inline
                    r.ImGui_PopItemWidth(ctx)
                    r.ImGui_SameLine(ctx)
                    local ok_disabled = (ui_settings.rename_inline_text:gsub("^%s+", ""):gsub("%s+$", "") == "")
                    if ok_disabled then r.ImGui_BeginDisabled(ctx, true) end
                    local ok_clicked = r.ImGui_Button(ctx, "OK", 120, ui_settings.button_height)
                    if ok_disabled then r.ImGui_EndDisabled(ctx) end
                    r.ImGui_SameLine(ctx)
                    local cancel_clicked = r.ImGui_Button(ctx, "Cancel", 120, ui_settings.button_height)
                    if ok_clicked or enter_pressed then
                        local trimmed = ui_settings.rename_inline_text:gsub("^%s+", ""):gsub("%s+$", "")
                        if trimmed == "" then
                            file_location.custom_folder_names[location] = nil
                        else
                            file_location.custom_folder_names[location] = trimmed
                        end
                        save_options()
                        file_location.renaming_location = nil
                        file_location.renaming_initialized = false
                        ui_settings.rename_inline_text = ""
                    elseif cancel_clicked then
                        file_location.renaming_location = nil
                        file_location.renaming_initialized = false
                        ui_settings.rename_inline_text = ""
                    end
                else
                    if r.ImGui_Button(ctx, folder_name, total_width, ui_settings.button_height) then
                    file_location.selected_location_index = i
                    file_location.current_location = location
                    clear_file_selection()
                    
                    if file_location.flat_view then
                        local files, timestamps, cache_time, metadata = load_file_cache(location)
                        if not files then
                            refresh_file_cache(location)
                        end
                        get_flat_file_list(location)
                    else
                        tree_cache.cache = {} 
                        file_location.current_files = read_directory_recursive(location, false)
                        search_filter.cached_location = ""
                        search_filter.cached_flat_files = {}
                        cached_metadata = {}
                    end
                    
                    file_location.last_folder_location = location
                    file_location.last_folder_index = i
                    
                    save_options()
                    end
                end
                r.ImGui_PopStyleColor(ctx, 1)
                if r.ImGui_BeginPopupContextItem(ctx) then
                    if r.ImGui_MenuItem(ctx, "Rename (Display Only)") then
                        file_location.rename_popup_location = nil
                        file_location.rename_popup_initialized = false
                        file_location.renaming_location = location
                        file_location.renaming_initialized = false
                    end
                    
                    if file_location.custom_folder_names[location] then
                        if r.ImGui_MenuItem(ctx, "Reset to Original Name") then
                            file_location.custom_folder_names[location] = nil
                            save_options()
                        end
                    end
                    
                    r.ImGui_Separator(ctx)
                    
                    if r.ImGui_BeginMenu(ctx, "Set Custom Color") then
                        local current_color = file_location.custom_folder_colors[location] or {h = 0.55, s = 0.8, v = 0.6}
                        
                        local r_val, g_val, b_val
                        local hue, sat, val = current_color.h, current_color.s, current_color.v
                        local i = math.floor(hue * 6)
                        local f = hue * 6 - i
                        local p = val * (1 - sat)
                        local q = val * (1 - f * sat)
                        local t = val * (1 - (1 - f) * sat)
                        i = i % 6
                        if i == 0 then r_val, g_val, b_val = val, t, p
                        elseif i == 1 then r_val, g_val, b_val = q, val, p
                        elseif i == 2 then r_val, g_val, b_val = p, val, t
                        elseif i == 3 then r_val, g_val, b_val = p, q, val
                        elseif i == 4 then r_val, g_val, b_val = t, p, val
                        else r_val, g_val, b_val = val, p, q
                        end
                        
                        local packed_color = (math.floor(r_val * 255) << 16) | (math.floor(g_val * 255) << 8) | math.floor(b_val * 255)
                        
                        local changed, new_color = r.ImGui_ColorPicker3(ctx, "##folder_color", packed_color, r.ImGui_ColorEditFlags_DisplayHSV())
                        if changed then
                            local new_r = ((new_color >> 16) & 0xFF) / 255
                            local new_g = ((new_color >> 8) & 0xFF) / 255
                            local new_b = (new_color & 0xFF) / 255
                            local h, s, v = rgb_to_hsv(new_r, new_g, new_b)
                            file_location.custom_folder_colors[location] = {h = h, s = s, v = v}
                            save_options()
                        end
                        r.ImGui_EndMenu(ctx)
                    end
                    
                    if file_location.custom_folder_colors[location] then
                        if r.ImGui_MenuItem(ctx, "Reset to Default Color") then
                            file_location.custom_folder_colors[location] = nil
                            save_options()
                        end
                    end
                    
                    r.ImGui_Separator(ctx)
                    
                    if r.ImGui_MenuItem(ctx, "Open in Explorer/Finder") then
                        local full_path = location
                        local command
                        if reaper.GetOS():match("Win") then
                            full_path = full_path:gsub("/", "\\")
                            command = string.format('explorer "%s"', full_path)
                        else
                            command = string.format('open "%s"', full_path)
                        end
                        os.execute(command)
                    end
                    
                    if r.ImGui_MenuItem(ctx, "Clear Cache for this Folder") then
                        local cache_file = cache_dir .. "file_cache_" .. location:gsub("[^%w]", "_") .. ".json"
                        if reaper.file_exists(cache_file) then
                            os.remove(cache_file)
                            cache_mgmt.scan_message = "Cache cleared for this folder"
                            cache_mgmt.message_timer = os.time()
                            if file_location.current_location == location then
                                search_filter.cached_location = ""
                                search_filter.cached_flat_files = {}
                                cached_metadata = {}
                            end
                        else
                            cache_mgmt.scan_message = "No cache found for this folder"
                            cache_mgmt.message_timer = os.time()
                        end
                    end
                    
                    if r.ImGui_MenuItem(ctx, "Refresh Folder Cache") then
                        if file_location.current_location == location then
                            refresh_file_cache(file_location.current_location)
                            search_filter.cached_location = ""
                            search_filter.cached_flat_files = {}
                            get_flat_file_list(file_location.current_location)
                            
                            if not file_location.flat_view then
                                file_location.current_files = read_directory_recursive(file_location.current_location, false)
                            end
                        else
                            local cache_file = cache_dir .. "file_cache_" .. location:gsub("[^%w]", "_") .. ".json"
                            if reaper.file_exists(cache_file) then
                                os.remove(cache_file)
                            end
                            cache_mgmt.scan_message = "Cache will refresh when folder is opened"
                            cache_mgmt.message_timer = os.time()
                        end
                    end
                    
                    r.ImGui_Separator(ctx)
                    
                    if r.ImGui_MenuItem(ctx, "Move Up") and i > 1 then
                        file_location.locations[i], file_location.locations[i-1] = file_location.locations[i-1], file_location.locations[i]
                        save_locations()
                    end
                    if r.ImGui_MenuItem(ctx, "Move Down") and i < #file_location.locations then
                        file_location.locations[i], file_location.locations[i+1] = file_location.locations[i+1], file_location.locations[i]
                        save_locations()
                    end
                    if r.ImGui_MenuItem(ctx, "Remove") then
                        table.remove(file_location.locations, i)
                        save_locations()
                        if i == file_location.selected_location_index then
                            file_location.selected_location_index = 1
                            file_location.current_location = file_location.locations[1] or ""
                            file_location.current_files = file_location.current_location ~= "" and read_directory_recursive(file_location.current_location) or {}
                        end
                    end
                    r.ImGui_EndPopup(ctx)
                end
            end
            local button_size = 24
            local pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
            local center_x = pos_x + total_width / 2
            local center_y = pos_y + button_size / 2
            if r.ImGui_InvisibleButton(ctx, "##AddLocation", total_width, button_size) then
                local retval, folder = r.JS_Dialog_BrowseForFolder(0, "Select Folder", "")
                if retval and folder ~= "" then
                    if not table.contains(file_location.locations, folder) then
                        table.insert(file_location.locations, folder)
                        save_locations()
                    end
                end
            end
            local drawList = r.ImGui_GetWindowDrawList(ctx)
            local circle_color = r.ImGui_IsItemHovered(ctx) and 0x808080FF or 0x606060FF
            local radius = button_size * 0.4
            r.ImGui_DrawList_AddCircle(drawList, center_x, center_y, radius, circle_color, 0, 1.5)
            local plus_size = radius * 0.6
            r.ImGui_DrawList_AddLine(drawList,
                center_x - plus_size, center_y,
                center_x + plus_size, center_y,
                circle_color, 1.5)
            r.ImGui_DrawList_AddLine(drawList,
                center_x, center_y - plus_size,
                center_x, center_y + plus_size,
                circle_color, 1.5)
            r.ImGui_PopStyleColor(ctx, 3) 
            r.ImGui_PopStyleVar(ctx, 1)
        end
        
        if ui.current_view_mode == "collections" then
            local total_width = reaper.ImGui_GetContentRegionAvail(ctx)
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 3)
            
            local unselected_button_color = r.ImGui_ColorConvertDouble4ToU32(ui_settings.button_brightness, ui_settings.button_brightness, ui_settings.button_brightness, 1.0)
            local button_text_color = r.ImGui_ColorConvertDouble4ToU32(ui_settings.button_text_brightness, ui_settings.button_text_brightness, ui_settings.button_text_brightness, 1.0)
            local accent_color = hsv_to_color(ui_settings.accent_hue, 1.0, 1.0)
            local accent_hover_color = hsv_to_color(ui_settings.accent_hue, 0.8, 1.0)
            local accent_active_color = hsv_to_color(ui_settings.accent_hue, 1.0, 0.8)
            
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), accent_hover_color)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), accent_active_color)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), button_text_color)
            
            for i, db_name in ipairs(file_location.collections) do
                local is_selected = (file_location.selected_collection == db_name)
                
                local base_color
                if is_selected then
                    base_color = accent_color
                elseif file_location.custom_collection_colors[db_name] then
                    local c = file_location.custom_collection_colors[db_name]
                    base_color = hsv_to_color(c.h, c.s, c.v)
                else
                    base_color = unselected_button_color
                end
                
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), base_color)
                
                local is_renaming = (file_location.renaming_collection == db_name)
                if is_renaming then
                    if not file_location.renaming_collection_initialized then
                        ui_settings.rename_inline_text = db_name
                        file_location.renaming_collection_initialized = true
                    end
                    r.ImGui_PushItemWidth(ctx, total_width - 260)
                    local enter_pressed, new_inline = r.ImGui_InputText(ctx, "##inline_rename_db_" .. i, ui_settings.rename_inline_text, r.ImGui_InputTextFlags_EnterReturnsTrue())
                    ui_settings.rename_inline_text = new_inline
                    r.ImGui_PopItemWidth(ctx)
                    r.ImGui_SameLine(ctx)
                    local ok_disabled = (ui_settings.rename_inline_text:gsub("^%s+", ""):gsub("%s+$", "") == "")
                    if ok_disabled then r.ImGui_BeginDisabled(ctx, true) end
                    local ok_clicked = r.ImGui_Button(ctx, "OK", 120, ui_settings.button_height)
                    if ok_disabled then r.ImGui_EndDisabled(ctx) end
                    r.ImGui_SameLine(ctx)
                    local cancel_clicked = r.ImGui_Button(ctx, "Cancel", 120, ui_settings.button_height)
                    if ok_clicked or enter_pressed then
                        local trimmed = ui_settings.rename_inline_text:gsub("^%s+", ""):gsub("%s+$", "")
                        if trimmed ~= "" and trimmed ~= db_name then
                            local success, msg = rename_collection(db_name, trimmed)
                            if not success then
                                r.ShowMessageBox("Error renaming collection: " .. (msg or "Unknown error"), "Rename Error", 0)
                            else
                                save_options()
                            end
                        end
                        file_location.renaming_collection = nil
                        file_location.renaming_collection_initialized = false
                        ui_settings.rename_inline_text = ""
                    elseif cancel_clicked then
                        file_location.renaming_collection = nil
                        file_location.renaming_collection_initialized = false
                        ui_settings.rename_inline_text = ""
                    end
                else
                    if r.ImGui_Button(ctx, db_name, total_width, ui_settings.button_height) then
                    file_location.selected_collection = db_name
                    file_location.selected_category = "All"  
                    
                    local db_data = load_collection(db_name)
                    if db_data then
                        local items = get_collection_items_by_category(db_name, file_location.selected_category)
                        file_location.current_files = {}
                        search_filter.cached_flat_files = {}
                        for _, item in ipairs(items) do
                            local file_entry = {
                                name = item.path:match("([^/\\]+)$"),
                                full_path = item.path,
                                is_dir = false
                            }
                            table.insert(file_location.current_files, file_entry)
                            table.insert(search_filter.cached_flat_files, file_entry)
                        end
                        file_location.current_location = "Collection: " .. db_name
                        search_filter.cached_location = file_location.current_location
                        search_filter.filtered_files = search_filter.cached_flat_files
                        file_location.flat_view = true
                        clear_file_selection()
                        
                        
                        file_location.last_collection_name = db_name
                        save_options()
                    end
                end
                end
                r.ImGui_PopStyleColor(ctx, 1)
                
                if r.ImGui_BeginPopupContextItem(ctx) then
                    if r.ImGui_MenuItem(ctx, "Rename") then
                        file_location.renaming_collection = db_name
                        file_location.renaming_collection_initialized = false
                    end
                    if r.ImGui_MenuItem(ctx, "Delete") then
                        delete_collection(db_name)
                        load_collections()
                        if file_location.selected_collection == db_name then
                            file_location.selected_collection = nil
                            file_location.current_files = {}
                        end
                    end
                    
                    r.ImGui_Separator(ctx)
                    
                    if r.ImGui_BeginMenu(ctx, "Set Custom Color") then
                        local current_color = file_location.custom_collection_colors[db_name] or {h = 0.55, s = 0.8, v = 0.6}
                        
                        local r_val, g_val, b_val
                        local hue, sat, val = current_color.h, current_color.s, current_color.v
                        local i = math.floor(hue * 6)
                        local f = hue * 6 - i
                        local p = val * (1 - sat)
                        local q = val * (1 - f * sat)
                        local t = val * (1 - (1 - f) * sat)
                        i = i % 6
                        if i == 0 then r_val, g_val, b_val = val, t, p
                        elseif i == 1 then r_val, g_val, b_val = q, val, p
                        elseif i == 2 then r_val, g_val, b_val = p, val, t
                        elseif i == 3 then r_val, g_val, b_val = p, q, val
                        elseif i == 4 then r_val, g_val, b_val = t, p, val
                        else r_val, g_val, b_val = val, p, q
                        end
                        
                        local packed_color = (math.floor(r_val * 255) << 16) | (math.floor(g_val * 255) << 8) | math.floor(b_val * 255)
                        
                        local changed, new_color = r.ImGui_ColorPicker3(ctx, "##collection_color", packed_color, r.ImGui_ColorEditFlags_DisplayHSV())
                        if changed then
                            local new_r = ((new_color >> 16) & 0xFF) / 255
                            local new_g = ((new_color >> 8) & 0xFF) / 255
                            local new_b = (new_color & 0xFF) / 255
                            local h, s, v = rgb_to_hsv(new_r, new_g, new_b)
                            file_location.custom_collection_colors[db_name] = {h = h, s = s, v = v}
                            save_options()
                        end
                        r.ImGui_EndMenu(ctx)
                    end
                    
                    if file_location.custom_collection_colors[db_name] then
                        if r.ImGui_MenuItem(ctx, "Reset to Default Color") then
                            file_location.custom_collection_colors[db_name] = nil
                            save_options()
                        end
                    end
                    
                    r.ImGui_EndPopup(ctx)
                end
            end
            
            local button_size = 24
            local pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
            local center_x = pos_x + total_width / 2
            local center_y = pos_y + button_size / 2
            
            if r.ImGui_InvisibleButton(ctx, "##AddCollection", total_width, button_size) then
                local retval, new_db_name = r.GetUserInputs("New Collection", 1, "Collection Name:", "")
                if retval and new_db_name ~= "" then
                    create_new_collection(new_db_name)
                    load_collections()
                end
            end
            
            local drawList = r.ImGui_GetWindowDrawList(ctx)
            local circle_color = r.ImGui_IsItemHovered(ctx) and 0x808080FF or 0x606060FF
            local radius = button_size * 0.4
            r.ImGui_DrawList_AddCircle(drawList, center_x, center_y, radius, circle_color, 0, 1.5)
            local plus_size = radius * 0.6
            r.ImGui_DrawList_AddLine(drawList,
                center_x - plus_size, center_y,
                center_x + plus_size, center_y,
                circle_color, 1.5)
            r.ImGui_DrawList_AddLine(drawList,
                center_x, center_y - plus_size,
                center_x, center_y + plus_size,
                circle_color, 1.5)
            
            r.ImGui_PopStyleColor(ctx, 3)  
            r.ImGui_PopStyleVar(ctx, 1)
        end
        
        r.ImGui_EndChild(ctx)
        
        if ui_settings.hide_scrollbar then
            r.ImGui_PopStyleVar(ctx, 1)
        end
        
        end
        if ui.show_oscilloscope then
            r.ImGui_Separator(ctx)
        end
        if ui.show_oscilloscope then
            -- Update audio buffer for oscilloscope and pitch detection - ALTERNATIVE METHOD
            if playback.playing_preview and playback.current_playing_file ~= "" then
                local current_time = r.time_precise()
                if current_time - (ui_settings.last_audio_update or 0) >= 0.05 then
                    ui_settings.last_audio_update = current_time
                    
                    -- Get current playback position  
                    local ok_pos, play_pos = r.CF_Preview_GetValue(playback.playing_preview, "D_POSITION")
                    
                    if ok_pos and play_pos and playback.playing_source then
                        local ok_srate, sample_rate = r.CF_Preview_GetValue(playback.playing_preview, "D_SRATE")
                        if not ok_srate then
                            sample_rate = r.GetMediaSourceSampleRate(playback.playing_source)
                        end
                        
                        if sample_rate then
                            -- Get peaks for pitch detection
                            local peaks_buf = r.new_array(ui_settings.buffer_size * 2)
                            r.PCM_Source_GetPeaks(playback.playing_source, sample_rate, play_pos, 1, ui_settings.buffer_size, 0, peaks_buf)
                            
                            ui_settings.audio_buffer = {}
                            for i = 1, ui_settings.buffer_size do
                                local idx_min = (i - 1) * 2 + 1
                                local idx_max = (i - 1) * 2 + 2
                                local min_val = peaks_buf[idx_min] or 0
                                local max_val = peaks_buf[idx_max] or 0
                                local sample = (min_val + max_val) / 2  -- Use average of min/max for better approximation
                                ui_settings.audio_buffer[i] = math.max(-1, math.min(1, sample))
                            end
                            
                            -- Optional: Apply simple low-pass filter to reduce noise for better pitch detection
                            -- local filtered_buffer = {}
                            -- for i = 1, #ui_settings.audio_buffer do
                            --     if i == 1 then
                            --         filtered_buffer[i] = ui_settings.audio_buffer[i]
                            --     else
                            --         filtered_buffer[i] = 0.7 * ui_settings.audio_buffer[i] + 0.3 * filtered_buffer[i-1]
                            --     end
                            -- end
                            -- ui_settings.audio_buffer = filtered_buffer
                            
                            if ui.pitch_detection_enabled and #ui_settings.audio_buffer > 200 and current_time - (waveform.last_pitch_update or 0) > 0.2 then
                                waveform.pitch_debug = "Analyzing..."
                                local success, detected_freq = pcall(detect_pitch_autocorrelation, ui_settings.audio_buffer, sample_rate)
                                
                                if success and detected_freq then
                                    -- Add to pitch history for smoothing
                                    table.insert(waveform.pitch_history, detected_freq)
                                    
                                    -- Keep only last 5 detections (longer history for better stability)
                                    while #waveform.pitch_history > 5 do
                                        table.remove(waveform.pitch_history, 1)
                                    end
                                    
                                    -- Calculate average pitch
                                    local avg_freq = 0
                                    for _, freq in ipairs(waveform.pitch_history) do
                                        avg_freq = avg_freq + freq
                                    end
                                    avg_freq = avg_freq / #waveform.pitch_history
                                    
                                    -- Only update stable pitch if we have enough history and pitch is reasonably consistent
                                    if #waveform.pitch_history >= 3 then
                                        -- Check consistency: all values should be within 15% of average (balanced for accuracy vs stability)
                                        local is_consistent = true
                                        for _, freq in ipairs(waveform.pitch_history) do
                                            if math.abs(freq - avg_freq) / avg_freq > 0.15 then
                                                is_consistent = false
                                                break
                                            end
                                        end
                                        
                                        if is_consistent then
                                            local new_stable_freq = avg_freq
                                            local new_stable_note = freq_to_note(avg_freq)
                                            
                                            -- Check if pitch changed
                                            if waveform.stable_pitch_hz and math.abs(new_stable_freq - waveform.stable_pitch_hz) / waveform.stable_pitch_hz < 0.05 then
                                                -- Same pitch, increase timer
                                                waveform.stable_pitch_timer = waveform.stable_pitch_timer + 0.2
                                            else
                                                -- Different pitch, reset timer
                                                waveform.stable_pitch_timer = 0
                                            end
                                            
                                            -- Only show stable pitch if it has been consistent for at least 0.6 seconds
                                            if waveform.stable_pitch_timer >= 0.6 then
                                                waveform.stable_pitch_hz = new_stable_freq
                                                waveform.stable_pitch_note = new_stable_note
                                            end
                                        else
                                            -- If not consistent, use the most recent detection but reset timer
                                            waveform.stable_pitch_timer = 0
                                            waveform.stable_pitch_hz = detected_freq
                                            waveform.stable_pitch_note = freq_to_note(detected_freq)
                                        end
                                    else
                                        -- Not enough history yet, use current detection
                                        waveform.stable_pitch_timer = 0
                                        waveform.stable_pitch_hz = detected_freq
                                        waveform.stable_pitch_note = freq_to_note(detected_freq)
                                    end
                                    
                                    waveform.current_pitch_hz = detected_freq
                                    waveform.current_pitch_note = freq_to_note(detected_freq)
                                    waveform.last_pitch_update = current_time
                                elseif not success then
                                    waveform.pitch_debug = "Error: " .. tostring(detected_freq):sub(1, 20)
                                    waveform.current_pitch_hz = nil
                                    waveform.current_pitch_note = nil
                                    waveform.stable_pitch_hz = nil
                                    waveform.stable_pitch_note = nil
                                    waveform.pitch_history = {}  -- Clear history on error
                                else
                                    -- detected_freq is nil (silence or low confidence)
                                    waveform.current_pitch_hz = nil
                                    waveform.current_pitch_note = nil
                                    waveform.stable_pitch_hz = nil
                                    waveform.stable_pitch_note = nil
                                    waveform.pitch_history = {}  -- Clear history when no pitch detected
                                end
                                waveform.last_pitch_update = current_time
                            elseif #ui_settings.audio_buffer <= 100 then
                                waveform.pitch_debug = "Buf too small: " .. #ui_settings.audio_buffer
                            end
                        end
                    end
                end
            end
            
            local draw_list = r.ImGui_GetWindowDrawList(ctx)
            local pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
            local width = r.ImGui_GetContentRegionAvail(ctx)
            local height = 120
            
            if ui.current_view_mode == "settings" then
                local texture = LoadTexture(settings_image_path)
                if texture then
                    local img_width = texture.width
                    local img_height = texture.height
                    local img_aspect = img_width / img_height
                    local osc_aspect = width / height
                    
                    local display_width, display_height
                    local offset_x, offset_y = 0, 0
                    
                    if img_aspect > osc_aspect then
                        display_width = width
                        display_height = width / img_aspect
                        offset_y = (height - display_height) / 2
                    else
                        display_height = height
                        display_width = height * img_aspect
                        offset_x = (width - display_width) / 2
                    end
                    
                    for i, color in ipairs(texture.pixels) do
                        local src_x = (i-1) % img_width
                        local src_y = math.floor((i-1) / img_width)
                        
                        local dst_x = pos_x + offset_x + (src_x / img_width) * display_width
                        local dst_y = pos_y + offset_y + (src_y / img_height) * display_height
                        local pixel_scale_x = display_width / img_width
                        local pixel_scale_y = display_height / img_height
                        
                        local blue = color & 0xFF
                        local green = (color >> 8) & 0xFF
                        local red = (color >> 16) & 0xFF
                        local alpha = (color >> 24) & 0xFF
                        local imgui_color = r.ImGui_ColorConvertDouble4ToU32(red/255, green/255, blue/255, alpha/255)
                        
                        r.ImGui_DrawList_AddRectFilled(draw_list,
                            dst_x,
                            dst_y,
                            dst_x + pixel_scale_x,
                            dst_y + pixel_scale_y,
                            imgui_color)
                    end
                else
                    local text = "SETTINGS IMAGE NOT FOUND"
                    local text_size_w, text_size_h = r.ImGui_CalcTextSize(ctx, text)
                    local text_x = pos_x + (width - text_size_w) / 2
                    local text_y = pos_y + (height - text_size_h) / 2
                    r.ImGui_DrawList_AddText(draw_list, text_x, text_y, 0xFF0000FF, text)
                end
            elseif playback.current_playing_file ~= "" then
                local ext = playback.current_playing_file:match("%.([^%.]+)$"):lower()
                local file_type = file_types[ext]
                if file_type == "REAPER_IMAGEFOLDER" then
                    local texture = LoadTexture(playback.current_playing_file)
                    if texture then
                        local img_width = texture.width
                        local img_height = texture.height
                        local img_aspect = img_width / img_height
                        local osc_aspect = width / height
                        
                        local display_width, display_height
                        local offset_x, offset_y = 0, 0
                        
                        if img_aspect > osc_aspect then
                            display_width = width
                            display_height = width / img_aspect
                            offset_y = (height - display_height) / 2
                        else
                            display_height = height
                            display_width = height * img_aspect
                            offset_x = (width - display_width) / 2
                        end
                        
                        for i, color in ipairs(texture.pixels) do
                            local src_x = (i-1) % img_width
                            local src_y = math.floor((i-1) / img_width)
                            
                            local dst_x = pos_x + offset_x + (src_x / img_width) * display_width
                            local dst_y = pos_y + offset_y + (src_y / img_height) * display_height
                            local pixel_scale_x = display_width / img_width
                            local pixel_scale_y = display_height / img_height
                            
                            local blue = color & 0xFF
                            local green = (color >> 8) & 0xFF
                            local red = (color >> 16) & 0xFF
                            local alpha = (color >> 24) & 0xFF
                            local imgui_color = r.ImGui_ColorConvertDouble4ToU32(red/255, green/255, blue/255, alpha/255)
                            
                            r.ImGui_DrawList_AddRectFilled(draw_list,
                                dst_x,
                                dst_y,
                                dst_x + pixel_scale_x,
                                dst_y + pixel_scale_y,
                                imgui_color)
                        end
                    end
                elseif file_type == "REAPER_VIDEOFOLDER" then
                    local center_x = pos_x + width / 2
                    local center_y = pos_y + height / 2
                    
                    local icon_size = 30
                    local triangle_p1_x = center_x - icon_size / 2
                    local triangle_p1_y = center_y - icon_size / 2
                    local triangle_p2_x = center_x - icon_size / 2
                    local triangle_p2_y = center_y + icon_size / 2
                    local triangle_p3_x = center_x + icon_size / 2
                    local triangle_p3_y = center_y
                    
                    r.ImGui_DrawList_AddTriangleFilled(draw_list,
                        triangle_p1_x, triangle_p1_y,
                        triangle_p2_x, triangle_p2_y,
                        triangle_p3_x, triangle_p3_y,
                        0xFFFFFFFF)
                    
                    r.ImGui_PushFont(ctx, normal_font, font_size)
                    local text = "VIDEO FILE"
                    local text_size_x = r.ImGui_CalcTextSize(ctx, text)
                    r.ImGui_DrawList_AddText(draw_list,
                        center_x - text_size_x / 2,
                        center_y + icon_size,
                        0xAAAAAAFF,
                        text)
                    r.ImGui_PopFont(ctx)
                    
                    r.ImGui_PushFont(ctx, small_font, small_font_size)
                    local hint = "Click Video button to view"
                    local hint_size_x = r.ImGui_CalcTextSize(ctx, hint)
                    r.ImGui_DrawList_AddText(draw_list,
                        center_x - hint_size_x / 2,
                        center_y + icon_size + 20,
                        0x888888FF,
                        hint)
                    r.ImGui_PopFont(ctx)
                elseif ext == "mid" or ext == "midi" then
                    if waveform.midi_info_message then
                        r.ImGui_PushFont(ctx, small_font, small_font_size)
                        local error_color = r.ImGui_ColorConvertDouble4ToU32(1.0, 0.3, 0.3, 1.0) 
                        
                        local lines = {}
                        for line in waveform.midi_info_message:gmatch("[^\n]+") do
                            table.insert(lines, line)
                        end
                        
                        local line_height = 14
                        local total_height = #lines * line_height
                        local start_y = pos_y + (height - total_height) / 2
                        
                        for i, line in ipairs(lines) do
                            local text_size_w = r.ImGui_CalcTextSize(ctx, line)
                            local text_x = pos_x + (width - text_size_w) / 2
                            local text_y = start_y + (i - 1) * line_height
                            r.ImGui_DrawList_AddText(draw_list, text_x, text_y, error_color, line)
                        end
                        r.ImGui_PopFont(ctx)
                    elseif waveform.midi_notes_file == playback.current_playing_file and #waveform.midi_notes > 0 then
                        local note_count = #waveform.midi_notes
                        local min_pitch = 127
                        local max_pitch = 0
                        local channels = {}
                        local total_velocity = 0
                        
                        for _, note in ipairs(waveform.midi_notes) do
                            if note.pitch < min_pitch then min_pitch = note.pitch end
                            if note.pitch > max_pitch then max_pitch = note.pitch end
                            channels[note.channel] = true
                            total_velocity = total_velocity + note.velocity
                        end
                        
                        local channel_count = 0
                        for _ in pairs(channels) do channel_count = channel_count + 1 end
                        local avg_velocity = math.floor(total_velocity / note_count)
                        
                        local note_names = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
                        local function pitch_to_name(pitch)
                            local octave = math.floor(pitch / 12) - 1
                            local note = note_names[(pitch % 12) + 1]
                            return note .. octave
                        end
                        
                        r.ImGui_PushFont(ctx, small_font, small_font_size)
                        local center_x = pos_x + width / 2
                        local start_y = pos_y + 10
                        local line_height = 14
                        
                        local text_color = r.ImGui_ColorConvertDouble4ToU32(
                            ui_settings.text_brightness,
                            ui_settings.text_brightness,
                            ui_settings.text_brightness,
                            1.0
                        )
                        
                        local playback_method = "ReaSynth"
                        if ui_settings.use_selected_track_for_midi then
                            playback_method = "Selected Track"
                        elseif ui_settings.use_numaplayer then
                            playback_method = "Numa Player"
                        end
                        
                        local info_lines = {
                            string.format("MIDI STATISTICS"),
                            string.format("Notes: %d", note_count),
                            string.format("Pitch Range: %s - %s", pitch_to_name(min_pitch), pitch_to_name(max_pitch)),
                            string.format("Channels: %d", channel_count),
                            string.format("Avg Velocity: %d", avg_velocity),
                            string.format("Playback: %s", playback_method)
                        }
                        
                        for i, line in ipairs(info_lines) do
                            local text_size_x = r.ImGui_CalcTextSize(ctx, line)
                            local text_x = center_x - text_size_x / 2
                            local text_y = start_y + (i - 1) * line_height
                            r.ImGui_DrawList_AddText(draw_list, text_x, text_y, text_color, line)
                        end
                        
                        r.ImGui_PopFont(ctx)
                    else
                        local text = "MIDI FILE"
                        local text_size_w, text_size_h = r.ImGui_CalcTextSize(ctx, text)
                        local text_x = pos_x + (width - text_size_w) / 2
                        local text_y = pos_y + (height - text_size_h) / 2
                        r.ImGui_DrawList_AddText(draw_list, text_x, text_y, 0x888888FF, text)
                    end
                else
                    local ext = playback.current_playing_file:match("%.([^%.]+)$")
                    local is_video_or_gif = false
                    if ext then
                        ext = ext:lower()
                        local video_extensions = {
                            mp4 = true, mov = true, avi = true, mkv = true, wmv = true,
                            flv = true, webm = true, m4v = true, mpg = true, mpeg = true,
                            gif = true
                        }
                        is_video_or_gif = video_extensions[ext] or false
                    end
                    
                    if playback.playing_preview and not playback.is_paused and not is_video_or_gif then
                        if playback.current_playing_file ~= "" then
                            local pixels = math.floor(width)
                            if waveform.oscilloscope_cache_file ~= playback.current_playing_file or #waveform.oscilloscope_cache ~= pixels then
                                waveform.oscilloscope_cache = {}
                                waveform.oscilloscope_cache_file = playback.current_playing_file
                                local source = r.PCM_Source_CreateFromFile(playback.current_playing_file)
                                if source then
                                    local length = r.GetMediaSourceLength(source)
                                    if length and length > 0 then
                                        local samplerate = 44100
                                        local numch = r.GetMediaSourceNumChannels(source) or 2
                                        local temp_track = r.GetTrack(0, 0)
                                        if temp_track then
                                            local num_items_before = r.CountTrackMediaItems(temp_track)
                                            local temp_item = r.AddMediaItemToTrack(temp_track)
                                            if temp_item then
                                                local take = r.AddTakeToMediaItem(temp_item)
                                                if take then
                                                    r.SetMediaItemTake_Source(take, source)
                                                    r.SetMediaItemLength(temp_item, length, false)
                                                    r.UpdateItemInProject(temp_item)
                                                    local accessor = r.CreateTakeAudioAccessor(take)
                                                    if accessor then
                                                        for i = 0, pixels - 1 do
                                                            local start_time = (i / pixels) * length
                                                            local samples_to_read = math.max(100, math.floor((length / pixels) * samplerate))
                                                            local buffer = r.new_array(samples_to_read * numch)
                                                            local ok = r.GetAudioAccessorSamples(accessor, samplerate, numch, start_time, samples_to_read, buffer)
                                                            local peak = 0
                                                            if ok > 0 then
                                                                for j = 1, ok * numch do
                                                                    local v = buffer[j] or 0
                                                                    if math.abs(v) > peak then peak = v end
                                                                end
                                                            end
                                                            waveform.oscilloscope_cache[i + 1] = peak
                                                            buffer.clear()
                                                        end
                                                        r.DestroyAudioAccessor(accessor)
                                                    end
                                                    r.DeleteTrackMediaItem(temp_track, temp_item)
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                            local accent_color = hsv_to_color(ui_settings.accent_hue, 1.0, 1.0)
                            
                            if #waveform.oscilloscope_cache > 0 and playback.playing_preview then
                                local retval, pos = r.CF_Preview_GetValue(playback.playing_preview, "D_POSITION")
                                local source = r.PCM_Source_CreateFromFile(playback.current_playing_file)
                                local file_length = 0
                                if source then
                                    file_length = r.GetMediaSourceLength(source) or 0
                                end
                                if file_length > 0 then
                                    local progress = pos / file_length
                                    local segment_width = 0.1  
                                    local start_idx = math.floor(progress * #waveform.oscilloscope_cache * (1 - segment_width))
                                    local end_idx = math.floor(start_idx + segment_width * #waveform.oscilloscope_cache)
                                    start_idx = math.max(1, start_idx)
                                    end_idx = math.min(#waveform.oscilloscope_cache, end_idx)

                                    for i = start_idx, end_idx - 1 do
                                        local local_i = i - start_idx + 1
                                        local x1 = pos_x + (local_i - 1) * width / (end_idx - start_idx)
                                        local y1 = pos_y + height/2 + waveform.oscilloscope_cache[i] * height/2
                                        local x2 = pos_x + local_i * width / (end_idx - start_idx)
                                        local y2 = pos_y + height/2 + waveform.oscilloscope_cache[i+1] * height/2
                                        r.ImGui_DrawList_AddLine(draw_list, x1, y1, x2, y2, accent_color, 1)
                                    end
                                    
                                    if ui.pitch_detection_enabled then
                                        r.ImGui_PushFont(ctx, small_font, small_font_size)
                                        
                                        local pitch_text = ""
                                        if playback.playing_preview and waveform.stable_pitch_note and waveform.stable_pitch_hz then
                                            pitch_text = waveform.stable_pitch_note .. " (" .. math.floor(waveform.stable_pitch_hz) .. "Hz)"
                                        end
                                        
                                        local text_w, text_h = r.ImGui_CalcTextSize(ctx, pitch_text)
                                        
                                        local padding = 8
                                        local box_padding = 5
                                        local button_radius = 4
                                        local button_margin = 5
                                        
                                        local button_x = pos_x + padding
                                        local button_y = pos_y + padding + box_padding + text_h / 2
                                        
                                        local box_x = button_x + button_radius * 2 + button_margin
                                        local box_y = pos_y + padding
                                        local box_w = 70
                                        local box_h = text_h + box_padding * 2
                                        local text_x = box_x + box_padding
                                        local text_y = box_y + box_padding
                                        
                                        local button_color = accent_color
                                        r.ImGui_DrawList_AddCircleFilled(draw_list, button_x, button_y, button_radius, button_color)
                                        
                                        r.ImGui_DrawList_AddRect(draw_list, 
                                            box_x, box_y, 
                                            box_x + box_w, box_y + box_h, 
                                            accent_color, 3, 0, 1)
                                        
                                        r.ImGui_DrawList_AddText(draw_list, text_x, text_y, accent_color, pitch_text)
                                        
                                        r.ImGui_PopFont(ctx)
                                    end
                                else
                                    r.ImGui_DrawList_AddLine(draw_list, pos_x, pos_y + height/2, pos_x + width, pos_y + height/2, accent_color, 1)
                                end
                            else
                                r.ImGui_DrawList_AddLine(draw_list, pos_x, pos_y + height/2, pos_x + width, pos_y + height/2, accent_color, 1)
                            end
                        else
                            r.ImGui_DrawList_AddLine(draw_list, pos_x, pos_y + height/2, pos_x + width, pos_y + height/2, accent_color, 1)
                        end
                    else
                        if playback.current_playing_file ~= "" and not is_video_or_gif then
                            local pixels = math.floor(width)
                            if waveform.oscilloscope_cache_file ~= playback.current_playing_file or #waveform.oscilloscope_cache ~= pixels then
                                waveform.oscilloscope_cache = {}
                                waveform.oscilloscope_cache_file = playback.current_playing_file
                                local source = r.PCM_Source_CreateFromFile(playback.current_playing_file)
                                if source then
                                    local length = r.GetMediaSourceLength(source)
                                    if length and length > 0 then
                                        local samplerate = 44100
                                        local numch = r.GetMediaSourceNumChannels(source) or 2
                                        local temp_track = r.GetTrack(0, 0)
                                        if temp_track then
                                            local num_items_before = r.CountTrackMediaItems(temp_track)
                                            local temp_item = r.AddMediaItemToTrack(temp_track)
                                            if temp_item then
                                                local take = r.AddTakeToMediaItem(temp_item)
                                                if take then
                                                    r.SetMediaItemTake_Source(take, source)
                                                    r.SetMediaItemLength(temp_item, length, false)
                                                    r.UpdateItemInProject(temp_item)
                                                    local accessor = r.CreateTakeAudioAccessor(take)
                                                    if accessor then
                                                        for i = 0, pixels - 1 do
                                                            local start_time = (i / pixels) * length
                                                            local samples_to_read = math.max(100, math.floor((length / pixels) * samplerate))
                                                            local buffer = r.new_array(samples_to_read * numch)
                                                            local ok = r.GetAudioAccessorSamples(accessor, samplerate, numch, start_time, samples_to_read, buffer)
                                                            local peak = 0
                                                            if ok > 0 then
                                                                for j = 1, ok * numch do
                                                                    local v = buffer[j] or 0
                                                                    if math.abs(v) > peak then peak = v end
                                                                end
                                                            end
                                                            waveform.oscilloscope_cache[i + 1] = peak
                                                            buffer.clear()
                                                        end
                                                        r.DestroyAudioAccessor(accessor)
                                                    end
                                                    r.DeleteTrackMediaItem(temp_track, temp_item)
                                                    if num_items_before == r.CountTrackMediaItems(temp_track) then
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                            local accent_color = hsv_to_color(ui_settings.accent_hue, 1.0, 1.0)
                            
                            if #waveform.oscilloscope_cache > 0 then
                                for i = 1, #waveform.oscilloscope_cache - 1 do
                                    local x1 = pos_x + (i-1) * width / #waveform.oscilloscope_cache
                                    local y1 = pos_y + height/2 + waveform.oscilloscope_cache[i] * height/2
                                    local x2 = pos_x + i * width / #waveform.oscilloscope_cache
                                    local y2 = pos_y + height/2 + waveform.oscilloscope_cache[i+1] * height/2
                                    r.ImGui_DrawList_AddLine(draw_list, x1, y1, x2, y2, accent_color, 1)
                                end
                            else
                                r.ImGui_DrawList_AddLine(draw_list, pos_x, pos_y + height/2, pos_x + width, pos_y + height/2, accent_color, 1)
                            end
                            
                            if ui.pitch_detection_enabled and playback.playing_preview then
                                r.ImGui_PushFont(ctx, normal_font, font_size)
                                
                                local pitch_text = waveform.current_pitch_note or "Detecting..."
                                local freq_text = waveform.current_pitch_hz and string.format("%.1f Hz", waveform.current_pitch_hz) or "No pitch"
                                
                                local pitch_w, pitch_h = r.ImGui_CalcTextSize(ctx, pitch_text)
                                local freq_w, freq_h = r.ImGui_CalcTextSize(ctx, freq_text)
                                
                                -- Position: top-left corner with padding
                                local padding = 10
                                local text_x = pos_x + padding
                                local pitch_y = pos_y + padding
                                local freq_y = pitch_y + pitch_h + 2
                                
                                -- Semi-transparent background
                                local bg_color = r.ImGui_ColorConvertDouble4ToU32(0, 0, 0, 0.7)
                                r.ImGui_DrawList_AddRectFilled(draw_list,
                                    text_x - 6, pitch_y - 4,
                                    text_x + math.max(pitch_w, freq_w) + 6, freq_y + freq_h + 4,
                                    bg_color, 4)
                                
                                -- Draw pitch text (larger, accent color)
                                local pitch_color = hsv_to_color(ui_settings.accent_hue, 1.0, 1.0)
                                r.ImGui_DrawList_AddText(draw_list, text_x, pitch_y, pitch_color, pitch_text)
                                
                                -- Draw frequency text (smaller, gray)
                                local freq_color = r.ImGui_ColorConvertDouble4ToU32(0.8, 0.8, 0.8, 1.0)
                                r.ImGui_DrawList_AddText(draw_list, text_x, freq_y, freq_color, freq_text)
                                
                                r.ImGui_PopFont(ctx)
                            end
                        else
                            local accent_color = hsv_to_color(ui_settings.accent_hue, 1.0, 1.0)
                            r.ImGui_DrawList_AddLine(draw_list, pos_x, pos_y + height/2, pos_x + width, pos_y + height/2, accent_color, 1)
                        end
                    end
                end
            else
                local text = "OSCILLOSCOPE"
                local text_size_w, text_size_h = r.ImGui_CalcTextSize(ctx, text)
                local text_x = pos_x + (width - text_size_w) / 2
                local text_y = pos_y + (height - text_size_h) / 2
                r.ImGui_DrawList_AddText(draw_list, text_x, text_y, 0x888888FF, text)
            end
            r.ImGui_Dummy(ctx, width, height)
        end
        r.ImGui_Separator(ctx)
        local total_available_width = r.ImGui_GetContentRegionAvail(ctx)
        local spacing_x, _ = r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing())
        local button_size = 15
        local num_buttons = 4
        local small_button_width = 30
        local small_button_height = 15
        local play_button_width = (total_available_width - (spacing_x * (3 - 1))) / 3
        local drawList = r.ImGui_GetWindowDrawList(ctx)
        local normal_color = r.ImGui_ColorConvertDouble4ToU32(ui_settings.text_brightness, ui_settings.text_brightness, ui_settings.text_brightness, 1.0)
        local hover_brightness = ui_settings.text_brightness < 0.5 and math.min(1.0, ui_settings.text_brightness + 0.3) or ui_settings.text_brightness * 0.8
        local hover_color = r.ImGui_ColorConvertDouble4ToU32(hover_brightness, hover_brightness, hover_brightness, 1.0)
        local active_color = hsv_to_color(ui_settings.accent_hue)
        local pause_active = hsv_to_color(ui_settings.accent_hue)
        local pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
        local play_state = playback.playing_preview and not playback.is_paused
        local file_to_play = playback.current_playing_file ~= "" and playback.current_playing_file or (playback.last_displayed_file ~= "" and playback.last_displayed_file or (ui.selected_index > 0 and ui.visible_files[ui.selected_index] and ui.visible_files[ui.selected_index].path) or "")
        if r.ImGui_InvisibleButton(ctx, "##Play", button_size, button_size) and file_to_play ~= "" then
            start_playback(file_to_play)
            if playback.link_transport then
                local reaper_state = r.GetPlayState()
                if reaper_state & 1 == 0 then 
                    r.CSurf_OnPlay()
                end
            end
        end
        local play_color = play_state and active_color or (r.ImGui_IsItemHovered(ctx) and hover_color or normal_color)
        r.ImGui_DrawList_AddTriangleFilled(drawList,
            pos_x + button_size * 0.2, pos_y + button_size * 0.1,
            pos_x + button_size * 0.2, pos_y + button_size * 0.9,
            pos_x + button_size * 0.9, pos_y + button_size * 0.5,
            play_color)
        r.ImGui_SameLine(ctx)
        pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
        local pause_state = playback.is_paused
        if r.ImGui_InvisibleButton(ctx, "##Pause", button_size, button_size) then
            local was_paused = playback.is_paused 
            pause_playback()
            if playback.link_transport and not playback.is_video_playback then
                local reaper_state = r.GetPlayState()
                if playback.is_paused and not was_paused then
                    if reaper_state & 1 == 1 then 
                        r.CSurf_OnPause()
                    end
                elseif not playback.is_paused and was_paused then
                    if reaper_state & 1 == 0 then  
                        r.CSurf_OnPlay()
                    end
                end
            end
        end
        local pause_color = pause_state and pause_active or (r.ImGui_IsItemHovered(ctx) and hover_color or normal_color)
        local bar_width = button_size * 0.25
        local center = pos_x + button_size * 0.5
        local gap = button_size * 0.15
        r.ImGui_DrawList_AddRectFilled(drawList,
            center - bar_width - gap/2, pos_y + button_size * 0.1,
            center - gap/2, pos_y + button_size * 0.9,
            pause_color)
        r.ImGui_DrawList_AddRectFilled(drawList,
            center + gap/2, pos_y + button_size * 0.1,
            center + bar_width + gap/2, pos_y + button_size * 0.9,
            pause_color)
        r.ImGui_SameLine(ctx)
        pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
        if r.ImGui_InvisibleButton(ctx, "##Stop", button_size, button_size) then
            stop_playback(false)
            if playback.link_transport then r.CSurf_OnStop() end
        end
        local stop_color = r.ImGui_IsItemHovered(ctx) and hover_color or normal_color
        r.ImGui_DrawList_AddRectFilled(drawList,
            pos_x + button_size * 0.12, pos_y + button_size * 0.12,
            pos_x + button_size * 0.88, pos_y + button_size * 0.88,
            stop_color)
        r.ImGui_SameLine(ctx)
        pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
        if r.ImGui_InvisibleButton(ctx, "##Loop", button_size, button_size) then
            playback.loop_play = not playback.loop_play
            save_options()
        end
        local loop_color = playback.loop_play and active_color or (r.ImGui_IsItemHovered(ctx) and hover_color or normal_color)
        local circle_center_x = pos_x + button_size * 0.5
        local circle_center_y = pos_y + button_size * 0.5
        local circle_radius = button_size * 0.35
        r.ImGui_DrawList_AddCircle(drawList,
            circle_center_x, circle_center_y,
            circle_radius,
            loop_color, 32, 2)
        local small_arrow_size = button_size * 0.24
        local left_arrow_x = circle_center_x - circle_radius
        local left_arrow_y = circle_center_y
        r.ImGui_DrawList_AddTriangleFilled(drawList,
            left_arrow_x, left_arrow_y - small_arrow_size/2,
            left_arrow_x - small_arrow_size/2, left_arrow_y + small_arrow_size/2,
            left_arrow_x + small_arrow_size/2, left_arrow_y + small_arrow_size/2,
            loop_color)
        local right_arrow_x = circle_center_x + circle_radius
        local right_arrow_y = circle_center_y
        r.ImGui_DrawList_AddTriangleFilled(drawList,
            right_arrow_x, right_arrow_y + small_arrow_size/2,
            right_arrow_x - small_arrow_size/2, right_arrow_y - small_arrow_size/2,
            right_arrow_x + small_arrow_size/2, right_arrow_y - small_arrow_size/2,
            loop_color)
        r.ImGui_SameLine(ctx, 0, 3)  
        
        local transport_start_x = r.ImGui_GetCursorPosX(ctx)
        local available_width = r.ImGui_GetContentRegionAvail(ctx)
        local toggle_size = 12
        local toggle_spacing = 3
        local buttons_width = small_button_width * 3 + 6  
        local transport_end_x = transport_start_x + available_width - toggle_size - toggle_spacing
        
        local button_line_y = r.ImGui_GetCursorPosY(ctx)
        
        r.ImGui_PushFont(ctx, medium_font, medium_font_size)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ButtonTextAlign(), 0.5, 0.5)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000000)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x00000000)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x00000000)
        local auto_text_color = playback.auto_play and active_color or r.ImGui_ColorConvertDouble4ToU32(
            ui_settings.text_brightness,
            ui_settings.text_brightness,
            ui_settings.text_brightness,
            1.0
        )
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), auto_text_color)
        if r.ImGui_Button(ctx, "auto", small_button_width, small_button_height) then
            playback.auto_play = not playback.auto_play
            save_options()
        end
        r.ImGui_PopStyleColor(ctx, 4)
        r.ImGui_PopStyleVar(ctx, 1)
        r.ImGui_PopFont(ctx)
        
        r.ImGui_SameLine(ctx, 0, 0)
        
        r.ImGui_PushFont(ctx, medium_font, medium_font_size)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ButtonTextAlign(), 0.5, 0.5)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000000)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x00000000)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x00000000)
        local sync_text_color = playback.use_original_speed and r.ImGui_ColorConvertDouble4ToU32(
            ui_settings.text_brightness,
            ui_settings.text_brightness,
            ui_settings.text_brightness,
            1.0
        ) or active_color
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), sync_text_color)
        if r.ImGui_Button(ctx, "sync", small_button_width, small_button_height) then
            playback.use_original_speed = not playback.use_original_speed
            playback.speed_manually_changed = true
            playback.pending_sync_refresh = true
            playback.last_sync_reference = nil
            local rate_multiplier = playback.current_playrate or 1.0
            local target_effective = rate_multiplier
            local base_rate_override = nil

            if not playback.use_original_speed then
                base_rate_override = get_sync_base_rate()
                if base_rate_override and base_rate_override > 0 then
                    target_effective = base_rate_override * rate_multiplier
                end
            end

            update_playrate(target_effective, base_rate_override)
            save_options()
        end
        r.ImGui_PopStyleColor(ctx, 4)
        r.ImGui_PopStyleVar(ctx, 1)
        r.ImGui_PopFont(ctx)
        
        r.ImGui_SameLine(ctx, 0, 0)
        
        r.ImGui_PushFont(ctx, medium_font, medium_font_size)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ButtonTextAlign(), 0.5, 0.5)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000000)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x00000000)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x00000000)
        local link_text_color = playback.link_transport and active_color or r.ImGui_ColorConvertDouble4ToU32(
            ui_settings.text_brightness,
            ui_settings.text_brightness,
            ui_settings.text_brightness,
            1.0
        )
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), link_text_color)
        if r.ImGui_Button(ctx, "link", small_button_width, small_button_height) then
            playback.link_transport = not playback.link_transport
            save_options()
        end
        
        if r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Link transport\nRight-click for options")
        end
        
        if r.ImGui_BeginPopupContextItem(ctx, "##LinkOptions") then
            local start_from_cursor = playback.link_start_from_editcursor
            if r.ImGui_Checkbox(ctx, "Start arrange from edit cursor", start_from_cursor) then
                playback.link_start_from_editcursor = not playback.link_start_from_editcursor
                save_options()
            end
            if r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, "When enabled: Arrange starts from current edit cursor position\nWhen disabled: Arrange starts at same position as media preview")
            end
            r.ImGui_EndPopup(ctx)
        end
        
        r.ImGui_PopStyleColor(ctx, 4)
        r.ImGui_PopStyleVar(ctx, 1)
        r.ImGui_PopFont(ctx)
        
        r.ImGui_SetCursorPos(ctx, transport_end_x, button_line_y)
        
        local toggle_size = 12
        local toggle_x, toggle_y = r.ImGui_GetCursorScreenPos(ctx)
        if r.ImGui_InvisibleButton(ctx, "##OscilloscopeToggle", toggle_size, toggle_size) then
            ui.show_oscilloscope = not ui.show_oscilloscope
            save_options()
        end
        local center_x = toggle_x + toggle_size / 2
        local center_y = toggle_y + toggle_size / 2
        local brightness = r.ImGui_IsItemHovered(ctx) and (ui_settings.text_brightness * 0.8) or ui_settings.text_brightness
        local line_color = r.ImGui_ColorConvertDouble4ToU32(brightness, brightness, brightness, 1.0)
        r.ImGui_DrawList_AddLine(drawList,
            center_x - toggle_size * 0.3, center_y,
            center_x + toggle_size * 0.3, center_y,
            line_color, 1.5)
        if not ui.show_oscilloscope then
            r.ImGui_DrawList_AddLine(drawList,
                center_x, center_y - toggle_size * 0.3,
                center_x, center_y + toggle_size * 0.3,
                line_color, 1.5)
        end
        r.ImGui_Separator(ctx)

        local available_width = r.ImGui_GetContentRegionAvail(ctx)
        local knob_size = 25
        local num_knobs = 3
        local total_spacing = (num_knobs - 1) * 40  
        local knob_spacing = (available_width - knob_size * num_knobs - total_spacing) / 2  
        local min_rate = playback.use_original_speed and 0.5 or 0.1
        local max_rate = playback.use_original_speed and 2.0 or 5.0
        local draw_list = r.ImGui_GetWindowDrawList(ctx)

        r.ImGui_SetCursorPosX(ctx, knob_spacing)
        local pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
        local vol_knob_center_x = pos_x + knob_size * 0.5
        local vol_knob_center_y = pos_y + knob_size * 0.5
        r.ImGui_InvisibleButton(ctx, "##VolKnob", knob_size, knob_size)
        local vol_angle = (linear_to_db(playback.preview_volume) - (-40)) / (12 - (-40)) * 270 - 135
        r.ImGui_DrawList_AddCircle(draw_list, vol_knob_center_x, vol_knob_center_y, knob_size * 0.43, 0xFFFFFFFF, 32, 1)
        r.ImGui_DrawList_AddCircle(draw_list, vol_knob_center_x, vol_knob_center_y, knob_size * 0.4, active_color, 32, 2)
        r.ImGui_DrawList_AddCircleFilled(draw_list, vol_knob_center_x, vol_knob_center_y, knob_size * 0.35, 0x404040FF, 32)
        local vol_indicator_x = vol_knob_center_x + math.cos(math.rad(vol_angle)) * knob_size * 0.25
        local vol_indicator_y = vol_knob_center_y + math.sin(math.rad(vol_angle)) * knob_size * 0.25
        r.ImGui_DrawList_AddLine(draw_list, vol_knob_center_x, vol_knob_center_y, vol_indicator_x, vol_indicator_y, 0xFFFFFFFF, 2)

        if r.ImGui_IsItemActivated(ctx) then
            ImGui_Knob_drag_y["volume"] = { y0 = select(2, r.ImGui_GetMousePos(ctx)), v0 = linear_to_db(playback.preview_volume) }
        elseif r.ImGui_IsItemActive(ctx) and ImGui_Knob_drag_y["volume"] then
            local cur_y = select(2, r.ImGui_GetMousePos(ctx))
            local delta = ImGui_Knob_drag_y["volume"].y0 - cur_y
            local step = (12 - (-40)) / (r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftCtrl()) and 2000 or r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftShift()) and 1000 or 100)
            local nv = ImGui_Knob_drag_y["volume"].v0 + delta * step
            local new_db = math.max(-40, math.min(12, nv))
            playback.preview_volume = db_to_linear(new_db)
            
            if playback.is_video_playback or playback.is_midi_playback then
                if playback.video_preview_track then
                    r.SetMediaTrackInfo_Value(playback.video_preview_track, "D_VOL", playback.preview_volume)
                end
            else
                if preview_track then
                    r.SetMediaTrackInfo_Value(preview_track, "D_VOL", playback.preview_volume)
                end
                if use_cf_view and CF_Preview then
                    r.CF_Preview_SetValue(CF_Preview, "D_VOLUME", playback.preview_volume)
                end
                if playback.playing_preview and not playback.is_paused then
                    r.CF_Preview_SetValue(playback.playing_preview, "D_VOLUME", playback.preview_volume)
                end
            end
        elseif not r.ImGui_IsItemActive(ctx) then
            ImGui_Knob_drag_y["volume"] = nil
        end

        r.ImGui_SameLine(ctx, 0, 40) 

        pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
        local rate_knob_center_x = pos_x + knob_size * 0.5
        local rate_knob_center_y = pos_y + knob_size * 0.5
        
        local rate_disabled = not playback.use_original_speed
        
        r.ImGui_InvisibleButton(ctx, "##RateKnob", knob_size, knob_size)
        
        local rate_angle = (playback.effective_playrate - min_rate) / (max_rate - min_rate) * 270 - 135
        
        local knob_alpha = rate_disabled and 0.5 or 1.0
        local outer_ring_color = r.ImGui_ColorConvertDouble4ToU32(1.0, 1.0, 1.0, knob_alpha)
        local inner_ring_color = rate_disabled and r.ImGui_ColorConvertDouble4ToU32(0.5, 0.5, 0.5, knob_alpha) or active_color
        local fill_color = r.ImGui_ColorConvertDouble4ToU32(0.25, 0.25, 0.25, knob_alpha)
        local indicator_color = r.ImGui_ColorConvertDouble4ToU32(1.0, 1.0, 1.0, knob_alpha)
        
        r.ImGui_DrawList_AddCircle(draw_list, rate_knob_center_x, rate_knob_center_y, knob_size * 0.43, outer_ring_color, 32, 1)
        r.ImGui_DrawList_AddCircle(draw_list, rate_knob_center_x, rate_knob_center_y, knob_size * 0.4, inner_ring_color, 32, 2)
        r.ImGui_DrawList_AddCircleFilled(draw_list, rate_knob_center_x, rate_knob_center_y, knob_size * 0.35, fill_color, 32)
        local rate_indicator_x = rate_knob_center_x + math.cos(math.rad(rate_angle)) * knob_size * 0.25
        local rate_indicator_y = rate_knob_center_y + math.sin(math.rad(rate_angle)) * knob_size * 0.25
        r.ImGui_DrawList_AddLine(draw_list, rate_knob_center_x, rate_knob_center_y, rate_indicator_x, rate_indicator_y, indicator_color, 2)

        if not rate_disabled then
            if r.ImGui_IsItemActivated(ctx) then
                ImGui_Knob_drag_y["rate"] = { y0 = select(2, r.ImGui_GetMousePos(ctx)), v0 = playback.effective_playrate }
            elseif r.ImGui_IsItemActive(ctx) and ImGui_Knob_drag_y["rate"] then
                local cur_y = select(2, r.ImGui_GetMousePos(ctx))
                local delta = ImGui_Knob_drag_y["rate"].y0 - cur_y
                local step = (max_rate - min_rate) / (r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftCtrl()) and 2000 or r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftShift()) and 1000 or 100)
                local nv = ImGui_Knob_drag_y["rate"].v0 + delta * step
                local new_rate = math.max(min_rate, math.min(max_rate, nv))
                update_playrate(new_rate)
            elseif not r.ImGui_IsItemActive(ctx) then
                ImGui_Knob_drag_y["rate"] = nil
            end
        end

        r.ImGui_SameLine(ctx, 0, 40) 

        pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
        local pitch_knob_center_x = pos_x + knob_size * 0.5
        local pitch_knob_center_y = pos_y + knob_size * 0.5
        r.ImGui_InvisibleButton(ctx, "##PitchKnob", knob_size, knob_size)
        local pitch_angle = (playback.current_pitch - (-12)) / (12 - (-12)) * 270 - 135
        r.ImGui_DrawList_AddCircle(draw_list, pitch_knob_center_x, pitch_knob_center_y, knob_size * 0.43, 0xFFFFFFFF, 32, 1)
        r.ImGui_DrawList_AddCircle(draw_list, pitch_knob_center_x, pitch_knob_center_y, knob_size * 0.4, active_color, 32, 2)
        r.ImGui_DrawList_AddCircleFilled(draw_list, pitch_knob_center_x, pitch_knob_center_y, knob_size * 0.35, 0x404040FF, 32)
        local pitch_indicator_x = pitch_knob_center_x + math.cos(math.rad(pitch_angle)) * knob_size * 0.25
        local pitch_indicator_y = pitch_knob_center_y + math.sin(math.rad(pitch_angle)) * knob_size * 0.25
        r.ImGui_DrawList_AddLine(draw_list, pitch_knob_center_x, pitch_knob_center_y, pitch_indicator_x, pitch_indicator_y, 0xFFFFFFFF, 2)

        if r.ImGui_IsItemActivated(ctx) then
            ImGui_Knob_drag_y["pitch"] = { y0 = select(2, r.ImGui_GetMousePos(ctx)), v0 = playback.current_pitch }
        elseif r.ImGui_IsItemActive(ctx) and ImGui_Knob_drag_y["pitch"] then
            local cur_y = select(2, r.ImGui_GetMousePos(ctx))
            local delta = ImGui_Knob_drag_y["pitch"].y0 - cur_y
            local step = (12 - (-12)) / (r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftCtrl()) and 2000 or r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftShift()) and 1000 or 100)
            local nv = ImGui_Knob_drag_y["pitch"].v0 + delta * step
            playback.current_pitch = math.floor(math.max(-12, math.min(12, nv)) + 0.5)
            if playback.playing_preview and not playback.is_paused then
                r.CF_Preview_SetValue(playback.playing_preview, "D_PITCH", playback.current_pitch)
            end
        elseif not r.ImGui_IsItemActive(ctx) then
            ImGui_Knob_drag_y["pitch"] = nil
        end

        if r.ImGui_IsMouseClicked(ctx, 1) then
            local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx)
            local vol_dist = math.sqrt((mouse_x - vol_knob_center_x)^2 + (mouse_y - vol_knob_center_y)^2)
            local rate_dist = math.sqrt((mouse_x - rate_knob_center_x)^2 + (mouse_y - rate_knob_center_y)^2)
            local pitch_dist = math.sqrt((mouse_x - pitch_knob_center_x)^2 + (mouse_y - pitch_knob_center_y)^2)

            if vol_dist < 20 then
                playback.preview_volume = 1.0
                if playback.is_video_playback or playback.is_midi_playback then
                    if playback.video_preview_track then
                        r.SetMediaTrackInfo_Value(playback.video_preview_track, "D_VOL", playback.preview_volume)
                    end
                else
                    if preview_track then
                        r.SetMediaTrackInfo_Value(preview_track, "D_VOL", playback.preview_volume)
                    end
                    if playback.playing_preview and not playback.is_paused then
                        r.CF_Preview_SetValue(playback.playing_preview, "D_VOLUME", playback.preview_volume)
                    end
                end
                ImGui_Knob_drag_y["volume"] = nil
            elseif rate_dist < 20 and playback.use_original_speed then
                update_playrate(1.0)
                ImGui_Knob_drag_y["rate"] = nil
            elseif pitch_dist < 20 then
                playback.current_pitch = 0
                if playback.playing_preview and not playback.is_paused then
                    r.CF_Preview_SetValue(playback.playing_preview, "D_PITCH", 0)
                end
                ImGui_Knob_drag_y["pitch"] = nil
            end
        end

        r.ImGui_PushFont(ctx, small_font, small_font_size)
        local value_y = r.ImGui_GetCursorPosY(ctx)

        local vol_text = "Vol " .. string.format("%.1f dB", linear_to_db(playback.preview_volume))
        local vol_text_w = r.ImGui_CalcTextSize(ctx, vol_text)
        r.ImGui_SetCursorPos(ctx, knob_spacing + knob_size * 0.5 - vol_text_w * 0.5, value_y)
        r.ImGui_Text(ctx, vol_text)

        local rate_text = "Rate " .. string.format("%.2fx", playback.effective_playrate)
        local rate_text_w = r.ImGui_CalcTextSize(ctx, rate_text)
        r.ImGui_SetCursorPos(ctx, knob_spacing + knob_size + 40 + knob_size * 0.5 - rate_text_w * 0.5, value_y)
        if not playback.use_original_speed then
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), r.ImGui_ColorConvertDouble4ToU32(
                ui_settings.text_brightness * 0.5,
                ui_settings.text_brightness * 0.5,
                ui_settings.text_brightness * 0.5,
                1.0
            ))
        end
        r.ImGui_Text(ctx, rate_text)
        if not playback.use_original_speed then
            r.ImGui_PopStyleColor(ctx, 1)
        end

        local pitch_text = "Pitch " .. string.format("%d st", playback.current_pitch)
        local pitch_text_w = r.ImGui_CalcTextSize(ctx, pitch_text)
        r.ImGui_SetCursorPos(ctx, knob_spacing + knob_size * 2 + 80 + knob_size * 0.5 - pitch_text_w * 0.5, value_y)
        r.ImGui_Text(ctx, pitch_text)

        r.ImGui_PopFont(ctx)
        r.ImGui_Separator(ctx)
        r.ImGui_Dummy(ctx, 0, 2)
        local width = r.ImGui_GetContentRegionAvail(ctx)
        local height = 12
        local draw_list = r.ImGui_GetWindowDrawList(ctx)
        local x, y = r.ImGui_GetCursorScreenPos(ctx)
        if playback.playing_preview and playback.current_playing_file ~= "" and playback.playing_source then
            local retval, pos = r.CF_Preview_GetValue(playback.playing_preview, "D_POSITION")
            local source_length = r.GetMediaSourceLength(playback.playing_source)
            pos = pos or 0
            source_length = source_length or 1
            local adjusted_length = source_length / (playback.effective_playrate or 1.0)
            local progress = math.min(pos / adjusted_length, 1)
            local red, green
            if progress < 0.6 then
                red = 0.0
                green = 1.0
            elseif progress < 0.9 then
                local fade = (progress - 0.6) / 0.3
                red = fade
                green = 1.0
            else
                local fade = (progress - 0.9) / 0.1
                red = 1.0
                green = 1.0 - fade
            end
            local bar_color = r.ImGui_ColorConvertDouble4ToU32(red, green, 0.0, 1.0)
            r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width * progress, y + height, bar_color)
            local adjusted_length = source_length / (playback.effective_playrate or 1.0)
            local time_text = string.format("%.2f / %.2f s", pos, adjusted_length)
            local text_w, text_h = r.ImGui_CalcTextSize(ctx, time_text)
            r.ImGui_DrawList_AddText(draw_list, x + (width - text_w) / 2, y + (height - text_h) / 2, 0xFFFFFFFF, time_text)
        else
            local text = "PROGRESS......"
            local text_size_w, text_size_h = r.ImGui_CalcTextSize(ctx, text)
            local text_x = x + (width - text_size_w) / 2
            local text_y = y + (height - text_size_h) / 2
            r.ImGui_DrawList_AddText(draw_list, text_x, text_y, 0x888888FF, text)
        end
        r.ImGui_Dummy(ctx, width, height)
        r.ImGui_EndChild(ctx)
        end
        r.ImGui_SameLine(ctx)
        local draw_list = r.ImGui_GetWindowDrawList(ctx)
        local x, y = r.ImGui_GetCursorScreenPos(ctx)
        local window_height = r.ImGui_GetWindowHeight(ctx)
        r.ImGui_DrawList_AddLine(draw_list, x, y, x, y + window_height, 0x606060FF, 1)
        r.ImGui_Dummy(ctx, 3, 0)
        r.ImGui_SameLine(ctx)
        if r.ImGui_BeginChild(ctx, "RightFileBrowserPanel", right_panel_width - 5, 0) then
            local FOOTER_H = 100
            local topbar_start_x = r.ImGui_GetCursorPosX(ctx)
            local quit_button_size = 20
            local settings_button_size = 20
            local video_button_size = 20
            local refresh_button_size = 20
            local spacing = 3
            if ui.current_view_mode == "settings" then
                local icons_width = refresh_button_size + video_button_size + settings_button_size + quit_button_size + (spacing * 4) + 10
                local dropdown_width = 20
                local title_width = r.ImGui_GetContentRegionAvail(ctx) - icons_width - dropdown_width - 3
                
                local settings_text_color = r.ImGui_ColorConvertDouble4ToU32(ui_settings.text_brightness, ui_settings.text_brightness, ui_settings.text_brightness, 1.0)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), 0x00000000) 
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), settings_text_color)
                r.ImGui_SetNextItemWidth(ctx, title_width)
                r.ImGui_InputText(ctx, "##SettingsTitle", "SETTINGS", r.ImGui_InputTextFlags_ReadOnly())
                r.ImGui_PopStyleColor(ctx, 2)
            else
                local icons_width = refresh_button_size + video_button_size + settings_button_size + quit_button_size + (spacing * 4) + 10
                local dropdown_width = 20
                local available_width = r.ImGui_GetContentRegionAvail(ctx) - icons_width - dropdown_width - 3
                
                local view_buttons_width = 0
                if ui.current_view_mode ~= "collections" then
                    local button_width = 40
                    view_buttons_width = (button_width * 2) + 5 + spacing
                    
                    local accent_color = hsv_to_color(ui_settings.accent_hue, 1.0, 1.0)
                    local button_bg = r.ImGui_ColorConvertDouble4ToU32(ui_settings.button_brightness, ui_settings.button_brightness, ui_settings.button_brightness, 1.0)
                    local text_col = r.ImGui_ColorConvertDouble4ToU32(ui_settings.button_text_brightness, ui_settings.button_text_brightness, ui_settings.button_text_brightness, 1.0)
                    
                    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 3)
                    
                    if file_location.flat_view then
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), accent_color)
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), r.ImGui_ColorConvertDouble4ToU32(0, 0, 0, 1))
                    else
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), button_bg)
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), text_col)
                    end
                    
                    if r.ImGui_Button(ctx, "Flat", button_width, 0) then
                        if not file_location.flat_view then
                            file_location.flat_view = true
                            search_filter.cached_location = ""
                            save_options()
                        end
                    end
                    
                    r.ImGui_PopStyleColor(ctx, 2)
                    
                    r.ImGui_SameLine(ctx, 0, 5)
                    
                    if not file_location.flat_view then
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), accent_color)
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), r.ImGui_ColorConvertDouble4ToU32(0, 0, 0, 1))
                    else
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), button_bg)
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), text_col)
                    end
                    
                    if r.ImGui_Button(ctx, "Tree", button_width, 0) then
                        if file_location.flat_view then
                            file_location.flat_view = false
                            search_filter.search_term = ""
                            search_filter.filtered_files = {}
                            tree_cache.cache = {}
                            if file_location.current_location ~= "" then
                                file_location.current_files = read_directory_recursive(file_location.current_location, false)
                            end
                            save_options()
                        end
                    end
                    
                    r.ImGui_PopStyleColor(ctx, 2)
                    r.ImGui_PopStyleVar(ctx, 1)
                    
                    r.ImGui_SameLine(ctx, 0, spacing)
                end
                
                local dropdown_button_width = 20
                local search_width = (available_width - view_buttons_width) * 0.5 + dropdown_button_width - 5
                
                local search_bg_color = r.ImGui_ColorConvertDouble4ToU32(ui_settings.button_brightness, ui_settings.button_brightness, ui_settings.button_brightness, 1.0)
                local search_hover_color = r.ImGui_ColorConvertDouble4ToU32(ui_settings.button_brightness * 1.2, ui_settings.button_brightness * 1.2, ui_settings.button_brightness * 1.2, 1.0)
                local text_color = r.ImGui_ColorConvertDouble4ToU32(ui_settings.text_brightness, ui_settings.text_brightness, ui_settings.text_brightness, 1.0)
                
                r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 3)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), search_bg_color)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), search_hover_color)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), search_hover_color)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), text_color)
                r.ImGui_SetNextItemWidth(ctx, search_width)
                local changed, new_search = r.ImGui_InputText(ctx, "##Search", search_filter.search_term)
            r.ImGui_PopStyleColor(ctx, 4)
            r.ImGui_PopStyleVar(ctx, 1)
            if changed then
                search_filter.search_term = new_search
                clear_sort_cache() 
                if file_location.flat_view and ui.current_view_mode ~= "collections" then
                    search_filter.filtered_files = {}
                    if search_filter.search_term ~= "" then
                        local search_lower = string.lower(search_filter.search_term)
                        for _, file in ipairs(search_filter.cached_flat_files) do
                            local name_lower = file.name_lower or string.lower(file.name)
                            local parent_lower = string.lower(file.parent_folder or "")
                            if string.find(name_lower, search_lower, 1, true) or string.find(parent_lower, search_lower, 1, true) then
                                table.insert(search_filter.filtered_files, file)
                            end
                        end
                    else
                        search_filter.filtered_files = search_filter.cached_flat_files
                    end
                elseif file_location.flat_view and ui.current_view_mode == "collections" then
                    search_filter.filtered_files = {}
                    if search_filter.search_term ~= "" then
                        local search_lower = string.lower(search_filter.search_term)
                        for _, file in ipairs(search_filter.cached_flat_files) do
                            local name_lower = file.name_lower or string.lower(file.name)
                            if string.find(name_lower, search_lower, 1, true) then
                                table.insert(search_filter.filtered_files, file)
                            end
                        end
                    else
                        search_filter.filtered_files = search_filter.cached_flat_files
                    end
                end
            end
            if r.ImGui_IsItemDeactivatedAfterEdit(ctx) and search_filter.search_term ~= "" then
                add_to_search_history(search_filter.search_term)
            end
            
            r.ImGui_SameLine(ctx, 0, 0)
            
            local transparent_color = r.ImGui_ColorConvertDouble4ToU32(0, 0, 0, 0)
            local accent_color = hsv_to_color(ui_settings.accent_hue, 1.0, 1.0)
            
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 3)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), transparent_color)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), transparent_color)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), transparent_color)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), accent_color)  
            if r.ImGui_ArrowButton(ctx, "##SearchHistory", r.ImGui_Dir_Down()) then
                r.ImGui_OpenPopup(ctx, "SearchHistoryPopup")
            end
            r.ImGui_PopStyleColor(ctx, 4)
            r.ImGui_PopStyleVar(ctx, 1)
            if r.ImGui_BeginPopup(ctx, "SearchHistoryPopup") then
                if #search_filter.search_history > 0 then
                    r.ImGui_Text(ctx, "search history:")
                    r.ImGui_Separator(ctx)
                    for i, history_term in ipairs(search_filter.search_history) do
                        if r.ImGui_Selectable(ctx, history_term, false) then
                            search_filter.search_term = history_term
                            if file_location.flat_view and ui.current_view_mode ~= "collections" then
                                search_filter.filtered_files = {}
                                if search_filter.search_term ~= "" then
                                    local search_lower = string.lower(search_filter.search_term)
                                    for _, file in ipairs(search_filter.cached_flat_files) do
                                        local name_lower = file.name_lower or string.lower(file.name)
                                        local parent_lower = string.lower(file.parent_folder or "")
                                        if string.find(name_lower, search_lower, 1, true) or string.find(parent_lower, search_lower, 1, true) then
                                            table.insert(search_filter.filtered_files, file)
                                        end
                                    end
                                else
                                    search_filter.filtered_files = search_filter.cached_flat_files
                                end
                            elseif file_location.flat_view and ui.current_view_mode == "collections" then
                                search_filter.filtered_files = {}
                                if search_filter.search_term ~= "" then
                                    local search_lower = string.lower(search_filter.search_term)
                                    for _, file in ipairs(search_filter.cached_flat_files) do
                                        local name_lower = file.name_lower or string.lower(file.name)
                                        if string.find(name_lower, search_lower, 1, true) then
                                            table.insert(search_filter.filtered_files, file)
                                        end
                                    end
                                else
                                    search_filter.filtered_files = search_filter.cached_flat_files
                                end
                            end
                            r.ImGui_CloseCurrentPopup(ctx)
                        end
                    end
                else
                    r.ImGui_Text(ctx, "No search history")
                end
                r.ImGui_EndPopup(ctx)
            end
            end  
            r.ImGui_SameLine(ctx)
            
            -- Display version
            local version_text = "v" .. script_version
            r.ImGui_PushFont(ctx, small_font, small_font_size)
            local version_width = r.ImGui_CalcTextSize(ctx, version_text)
            local version_y = r.ImGui_GetCursorPosY(ctx)
            r.ImGui_SetCursorPosY(ctx, version_y + 2)  -- Slight vertical offset for alignment
            local version_brightness = ui_settings.text_brightness * 0.6
            local version_color = r.ImGui_ColorConvertDouble4ToU32(version_brightness, version_brightness, version_brightness, 1.0)
            r.ImGui_TextColored(ctx, version_color, version_text)
            r.ImGui_PopFont(ctx)
            r.ImGui_SameLine(ctx, 0, 8)  -- 8px spacing after version
            
            local avail_width = r.ImGui_GetContentRegionAvail(ctx)
            local quit_button_size = 10
            local settings_button_size = 20
            local video_button_size = 20
            local refresh_button_size = 20
            local spacing = 3
            local offset_left = 5
            local offset_up = 3
            local buttons_y = r.ImGui_GetCursorPosY(ctx) - offset_up
            
            local is_folder_view = ui.current_view_mode == "folders"
            local refresh_enabled = is_folder_view and file_location.current_location ~= ""
            
            local button_count = refresh_enabled and 4 or 3
            r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + avail_width - (refresh_enabled and refresh_button_size or 0) - video_button_size - settings_button_size - settings_button_size - quit_button_size - offset_left - (spacing * button_count) - 1)
            r.ImGui_SetCursorPosY(ctx, buttons_y)
            
            local drawList = r.ImGui_GetWindowDrawList(ctx)
            local base_color = r.ImGui_ColorConvertDouble4ToU32(ui_settings.text_brightness, ui_settings.text_brightness, ui_settings.text_brightness, 1.0)
            local hover_brightness = ui_settings.text_brightness < 0.5 and math.min(1.0, ui_settings.text_brightness + 0.3) or ui_settings.text_brightness * 0.8
            local hover_color = r.ImGui_ColorConvertDouble4ToU32(hover_brightness, hover_brightness, hover_brightness, 1.0)
            
            if refresh_enabled then
                local refresh_pos_x, refresh_pos_y = r.ImGui_GetCursorScreenPos(ctx)
                if r.ImGui_InvisibleButton(ctx, "##refresh", refresh_button_size, refresh_button_size) then
                    tree_cache.cache[file_location.current_location] = nil
                    
                    
                    refresh_file_cache(file_location.current_location)
                    search_filter.cached_location = ""
                    search_filter.cached_flat_files = {}
                    get_flat_file_list(file_location.current_location)
                    
                    if not file_location.flat_view then
                        file_location.current_files = read_directory_recursive(file_location.current_location, false)
                    end
                end
                local refresh_color = r.ImGui_IsItemHovered(ctx) and hover_color or base_color
                local center_x = refresh_pos_x + refresh_button_size / 2
                local center_y = refresh_pos_y + refresh_button_size / 2
                local radius = refresh_button_size * 0.35
                r.ImGui_DrawList_AddCircle(drawList, center_x, center_y, radius, refresh_color, 0, 1.5)
                local arrow_size = radius * 0.6
                local arrow_points = {
                    {x = center_x + arrow_size * 0.5, y = center_y},
                    {x = center_x - arrow_size * 0.3, y = center_y - arrow_size * 0.3},
                    {x = center_x - arrow_size * 0.3, y = center_y + arrow_size * 0.3}
                }
                r.ImGui_DrawList_AddTriangleFilled(drawList, arrow_points[1].x, arrow_points[1].y, arrow_points[2].x, arrow_points[2].y, arrow_points[3].x, arrow_points[3].y, refresh_color)
                if r.ImGui_IsItemHovered(ctx) then
                    r.ImGui_SetTooltip(ctx, "Refresh folder cache (incremental scan)")
                end
                r.ImGui_SameLine(ctx, 0, spacing - 1)
            end
            r.ImGui_SetCursorPosY(ctx, buttons_y)
            local video_pos_x, video_pos_y = r.ImGui_GetCursorScreenPos(ctx)
            if r.ImGui_InvisibleButton(ctx, "##video", video_button_size, video_button_size) then
                r.Main_OnCommand(50125, 0) 
            end
            local drawList = r.ImGui_GetWindowDrawList(ctx)
            local video_is_open = is_video_window_open()
            local accent_color = hsv_to_color(ui_settings.accent_hue)
            local icon_color = video_is_open and accent_color or (r.ImGui_IsItemHovered(ctx) and hover_color or base_color)
            local center_x = video_pos_x + video_button_size / 2
            local center_y = video_pos_y + video_button_size / 2
            local screen_width = video_button_size * 0.6
            local screen_height = video_button_size * 0.5
            r.ImGui_DrawList_AddRect(drawList,
                center_x - screen_width/2, center_y - screen_height/2,
                center_x + screen_width/2, center_y + screen_height/2,
                icon_color, 1, 0, 1.5)
            local stand_width = screen_width * 0.3
            local stand_height = screen_height * 0.15
            r.ImGui_DrawList_AddRectFilled(drawList,
                center_x - stand_width/2, center_y + screen_height/2,
                center_x + stand_width/2, center_y + screen_height/2 + stand_height,
                icon_color)
            if r.ImGui_IsItemHovered(ctx) then
                local tooltip_text = video_is_open and "Video Window (Open - Click to Close)" or "Video Window (Closed - Click to Open)"
                r.ImGui_SetTooltip(ctx, tooltip_text)
            end
            r.ImGui_SameLine(ctx, 0, spacing - 1)
            r.ImGui_SetCursorPosY(ctx, buttons_y)
            local settings_pos_x, settings_pos_y = r.ImGui_GetCursorScreenPos(ctx)
            if r.ImGui_InvisibleButton(ctx, "##settings", settings_button_size, settings_button_size) then
                if ui.current_view_mode ~= "settings" then
                    ui.current_view_mode = "settings"
                else
                    ui.current_view_mode = "folders"
                end
                save_options()
            end
            local settings_color = r.ImGui_IsItemHovered(ctx) and hover_color or base_color
            local gear_center_x = settings_pos_x + settings_button_size / 2
            local gear_center_y = settings_pos_y + settings_button_size / 2
            local gear_radius = settings_button_size * 0.35
            local inner_radius = gear_radius * 0.5
            r.ImGui_DrawList_AddCircle(drawList, gear_center_x, gear_center_y, gear_radius, settings_color, 0, 1.5)
            r.ImGui_DrawList_AddCircle(drawList, gear_center_x, gear_center_y, inner_radius, settings_color, 0, 1.5)
            if r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, "Settings")
            end
            
            -- Shortcuts button (keyboard icon)
            r.ImGui_SameLine(ctx, 0, spacing - 1)
            r.ImGui_SetCursorPosY(ctx, buttons_y)
            local shortcuts_pos_x, shortcuts_pos_y = r.ImGui_GetCursorScreenPos(ctx)
            if r.ImGui_InvisibleButton(ctx, "##shortcuts", settings_button_size, settings_button_size) then
                if ui.current_view_mode ~= "shortcuts" then
                    ui.current_view_mode = "shortcuts"
                else
                    ui.current_view_mode = "folders"
                end
            end
            local shortcuts_color = r.ImGui_IsItemHovered(ctx) and hover_color or base_color
            local kb_center_x = shortcuts_pos_x + settings_button_size / 2
            local kb_center_y = shortcuts_pos_y + settings_button_size / 2
            local kb_w = settings_button_size * 0.7
            local kb_h = kb_w * 0.6
            local kb_x = kb_center_x - kb_w / 2
            local kb_y = kb_center_y - kb_h / 2
            r.ImGui_DrawList_AddRect(drawList, kb_x, kb_y, kb_x + kb_w, kb_y + kb_h, shortcuts_color, 2, 0, 1.5)
            local key_w = kb_w * 0.22
            local key_h = kb_h * 0.55
            local key_y = kb_y + kb_h * 0.22
            local key_spacing = kb_w * 0.08
            for i = 0, 2 do
                local key_x = kb_x + kb_w * 0.12 + i * (key_w + key_spacing)
                r.ImGui_DrawList_AddRectFilled(drawList, key_x, key_y, key_x + key_w, key_y + key_h, shortcuts_color, 1)
            end
            if r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, "Keyboard Shortcuts")
            end
            
            r.ImGui_SameLine(ctx, 0, spacing + 2)
            r.ImGui_SetCursorPosY(ctx, buttons_y + 5)
            if r.ImGui_InvisibleButton(ctx, "##quit", quit_button_size, quit_button_size) then
                open = false
            end
            if r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, "Close")
            end
            local quit_color = r.ImGui_IsItemHovered(ctx) and hover_color or base_color
            local quit_pos_x, quit_pos_y = r.ImGui_GetItemRectMin(ctx)
            local quit_center_x = quit_pos_x + quit_button_size / 2
            local quit_center_y = quit_pos_y + quit_button_size / 2
            local radius = 6.8
            local cross_size = 3.5
            r.ImGui_DrawList_AddCircle(drawList, quit_center_x, quit_center_y, radius, quit_color, 0, 2)
            r.ImGui_DrawList_AddLine(drawList,
                quit_center_x - cross_size, quit_center_y - cross_size,
                quit_center_x + cross_size, quit_center_y + cross_size,
                quit_color, 2)
            r.ImGui_DrawList_AddLine(drawList,
                quit_center_x + cross_size, quit_center_y - cross_size,
                quit_center_x - cross_size, quit_center_y + cross_size,
                quit_color, 2)
            
            r.ImGui_Separator(ctx)
            
            if ui.current_view_mode == "collections" and file_location.selected_collection then
                local db = load_collection(file_location.selected_collection)
                if db then
                    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 3)
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x404040FF)
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x505050FF)
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x606060FF)
                    if r.ImGui_Button(ctx, "Set Categories") then
                        file_location.show_category_manager = true
                    end
                    r.ImGui_PopStyleColor(ctx, 3)
                    r.ImGui_PopStyleVar(ctx, 1)
                    
                    if db.categories and #db.categories > 0 then
                        r.ImGui_SameLine(ctx, 0, 5)
                        r.ImGui_Text(ctx, "Filter:")
                        r.ImGui_SameLine(ctx, 0, 5)
                        r.ImGui_SetNextItemWidth(ctx, 120)
                        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 3)
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), 0x404040FF)
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), 0x505050FF)
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), 0x505050FF)
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x404040FF)
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x505050FF)
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x606060FF)
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFFFFFFFF)
                        
                        local item_count = #db.categories + 1
                        local item_height = r.ImGui_GetTextLineHeightWithSpacing(ctx)
                        local max_height = item_height * item_count + 10
                        r.ImGui_SetNextWindowSizeConstraints(ctx, 120, max_height, 300, max_height)
                        
                        if r.ImGui_BeginCombo(ctx, "##CategoryFilter", file_location.selected_category) then
                            if r.ImGui_Selectable(ctx, "All", file_location.selected_category == "All") then
                                file_location.selected_category = "All"
                                local items = get_collection_items_by_category(file_location.selected_collection, "All")
                                file_location.current_files = {}
                                search_filter.cached_flat_files = {}
                                for _, item in ipairs(items) do
                                    local file_entry = {
                                        name = item.path:match("([^/\\]+)$"),
                                        full_path = item.path,
                                        is_dir = false
                                    }
                                    table.insert(file_location.current_files, file_entry)
                                    table.insert(search_filter.cached_flat_files, file_entry)
                                end
                                search_filter.filtered_files = search_filter.cached_flat_files
                            end
                            for _, cat in ipairs(db.categories) do
                                if r.ImGui_Selectable(ctx, cat, file_location.selected_category == cat) then
                                    file_location.selected_category = cat
                                    local items = get_collection_items_by_category(file_location.selected_collection, cat)
                                    file_location.current_files = {}
                                    search_filter.cached_flat_files = {}
                                    for _, item in ipairs(items) do
                                        local file_entry = {
                                            name = item.path:match("([^/\\]+)$"),
                                            full_path = item.path,
                                            is_dir = false
                                        }
                                        table.insert(file_location.current_files, file_entry)
                                        table.insert(search_filter.cached_flat_files, file_entry)
                                    end
                                    search_filter.filtered_files = search_filter.cached_flat_files
                                end
                            end
                            r.ImGui_EndCombo(ctx)
                        end
                        r.ImGui_PopStyleColor(ctx, 7)
                        r.ImGui_PopStyleVar(ctx, 1)
                    end
                    r.ImGui_SameLine(ctx, 0, 15)
            end
        end
        
        if ui.current_view_mode ~= "settings" and ui.current_view_mode ~= "shortcuts" then
            if (file_location.flat_view and file_location.current_location ~= "") or ui.current_view_mode == "collections" then
                if ui.current_view_mode ~= "collections" then
                    r.ImGui_Dummy(ctx, 0, 3)
                    r.ImGui_SameLine(ctx, 0, 1)
                else
                    r.ImGui_Dummy(ctx, 0, 3)
                end
                r.ImGui_Text(ctx, string.format("%d files", #search_filter.filtered_files))
                
                r.ImGui_SameLine(ctx, 0, 10)
                
                local transparent = r.ImGui_ColorConvertDouble4ToU32(0, 0, 0, 0)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), transparent)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), transparent)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), transparent)
                r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 0, 0)  
                
                if r.ImGui_Button(ctx, "Start") then
                    if #ui.visible_files > 0 then
                        ui.selected_index = 1
                        ui.scroll_to_top = true  
                    end
                end
                
                r.ImGui_PopStyleVar(ctx, 1)
                r.ImGui_PopStyleColor(ctx, 3)
            end
        end
        
        if ui.current_view_mode ~= "settings" and ui.current_view_mode ~= "shortcuts" then
            r.ImGui_Separator(ctx)
        end
        
        local scrollbar_pushed = false
        if ui_settings.hide_scrollbar then
                r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ScrollbarSize(), 0)
                scrollbar_pushed = true
            end
            
            if r.ImGui_BeginChild(ctx, "RightPanelContent", 0, -FOOTER_H) then
                if ui.current_view_mode == "settings" then
                    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 3)
                    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(), 3)
                    
                    local accent_color = hsv_to_color(ui_settings.accent_hue)
                    local accent_hover = hsv_to_color(ui_settings.accent_hue, 1.0, 0.8)
                    local accent_active = hsv_to_color(ui_settings.accent_hue, 1.0, 0.6)
                    
                    local button_color = r.ImGui_ColorConvertDouble4ToU32(ui_settings.button_brightness, ui_settings.button_brightness, ui_settings.button_brightness, 1.0)
                    local button_hover = r.ImGui_ColorConvertDouble4ToU32(ui_settings.button_brightness * 1.2, ui_settings.button_brightness * 1.2, ui_settings.button_brightness * 1.2, 1.0)
                    local button_active = r.ImGui_ColorConvertDouble4ToU32(ui_settings.button_brightness * 1.4, ui_settings.button_brightness * 1.4, ui_settings.button_brightness * 1.4, 1.0)
                    
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), accent_color)
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), accent_active)
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), button_color)
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), button_hover)
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), button_active)
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), button_color)
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), button_hover)
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), button_active)
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), accent_color)
                    
                    r.ImGui_Spacing(ctx)
                    
                    local header_color = r.ImGui_ColorConvertDouble4ToU32(ui_settings.text_brightness, ui_settings.text_brightness, ui_settings.text_brightness, 1.0)
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), header_color)
                    r.ImGui_SeparatorText(ctx, "Settings Presets")
                    r.ImGui_PopStyleColor(ctx, 1)
                    
                    r.ImGui_Spacing(ctx)
                    
                    local preset_list = get_preset_list()
                    if not ui.selected_preset_index then ui.selected_preset_index = 1 end
                    if not ui.new_preset_name then ui.new_preset_name = "" end
                    
                    if #preset_list > 0 then
                        r.ImGui_Text(ctx, "Available Presets:")
                        r.ImGui_SetNextItemWidth(ctx, 300)
                        local combo_items = table.concat(preset_list, "\0") .. "\0"
                        local changed, new_index = r.ImGui_Combo(ctx, "##presets", ui.selected_preset_index - 1, combo_items)
                        if changed then
                            ui.selected_preset_index = new_index + 1
                        end
                        
                        r.ImGui_SameLine(ctx)
                        if r.ImGui_Button(ctx, "Load Preset") then
                            if preset_list[ui.selected_preset_index] then
                                local success, error_msg = load_preset(preset_list[ui.selected_preset_index])
                                if not success then
                                    r.ShowMessageBox("Failed to load preset: " .. error_msg, "Error", 0)
                                end
                            end
                        end
                        
                        r.ImGui_SameLine(ctx)
                        if r.ImGui_Button(ctx, "Resave") then
                            if preset_list[ui.selected_preset_index] then
                                local preset_name = preset_list[ui.selected_preset_index]
                                if save_preset(preset_name) then
                                else
                                    r.ShowMessageBox("Failed to resave preset", "Error", 0)
                                end
                            end
                        end
                        
                        r.ImGui_SameLine(ctx)
                        if r.ImGui_Button(ctx, "Delete") then
                            if preset_list[ui.selected_preset_index] then
                                local ret = r.ShowMessageBox("Delete preset '" .. preset_list[ui.selected_preset_index] .. "'?", "Confirm", 4)
                                if ret == 6 then 
                                    delete_preset(preset_list[ui.selected_preset_index])
                                    ui.selected_preset_index = 1
                                end
                            end
                        end
                    else
                        r.ImGui_Text(ctx, "No presets found")
                    end
                    
                    r.ImGui_Spacing(ctx)
                    r.ImGui_Text(ctx, "Save Current Settings as Preset:")
                    r.ImGui_SetNextItemWidth(ctx, 300)
                    local ret, new_name = r.ImGui_InputText(ctx, "##preset_name", ui.new_preset_name)
                    if ret then
                        ui.new_preset_name = new_name
                    end
                    
                    r.ImGui_SameLine(ctx)
                    if r.ImGui_Button(ctx, "Save Preset") then
                        if ui.new_preset_name and ui.new_preset_name ~= "" then
                            if save_preset(ui.new_preset_name) then
                                ui.new_preset_name = ""
                            else
                                r.ShowMessageBox("Failed to save preset", "Error", 0)
                            end
                        else
                            r.ShowMessageBox("Please enter a preset name", "Error", 0)
                        end
                    end
                    
                    r.ImGui_Spacing(ctx)
                    r.ImGui_Spacing(ctx)
                    
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), header_color)
                    r.ImGui_SeparatorText(ctx, "GUI Styling")
                    r.ImGui_PopStyleColor(ctx, 1)
                    
                    r.ImGui_Spacing(ctx)
                    
                    local bg_changed, new_bg = r.ImGui_SliderDouble(ctx, "Window Color (Black to White)", ui_settings.window_bg_brightness, 0.0, 1.0, "%.2f")
                    if bg_changed then
                        ui_settings.window_bg_brightness = new_bg
                        save_options()
                    end
                    
                    r.ImGui_Spacing(ctx)
                    local opacity_changed, new_opacity = r.ImGui_SliderDouble(ctx, "Window Opacity", ui_settings.window_opacity, 0.0, 1.0, "%.2f")
                    if opacity_changed then
                        ui_settings.window_opacity = new_opacity
                        save_options()
                    end
                    
                    r.ImGui_Spacing(ctx)
                    local text_changed, new_text = r.ImGui_SliderDouble(ctx, "Text Color (Black to White)", ui_settings.text_brightness, 0.0, 1.0, "%.2f")
                    if text_changed then
                        ui_settings.text_brightness = new_text
                        save_options()
                    end
                    
                    r.ImGui_Spacing(ctx)
                    local grid_changed, new_grid = r.ImGui_SliderDouble(ctx, "Grid & Ruler Color (Black to White)", ui_settings.grid_brightness, 0.0, 1.0, "%.2f")
                    if grid_changed then
                        ui_settings.grid_brightness = new_grid
                        save_options()
                    end
                    
                    r.ImGui_Spacing(ctx)
                    local button_changed, new_button = r.ImGui_SliderDouble(ctx, "Button Color (Black to White)", ui_settings.button_brightness, 0.0, 1.0, "%.2f")
                    if button_changed then
                        ui_settings.button_brightness = new_button
                        save_options()
                    end
                    
                    r.ImGui_Spacing(ctx)
                    local button_text_changed, new_button_text = r.ImGui_SliderDouble(ctx, "Button Text Color (Black to White)", ui_settings.button_text_brightness, 0.0, 1.0, "%.2f")
                    if button_text_changed then
                        ui_settings.button_text_brightness = new_button_text
                        save_options()
                    end
                    
                    r.ImGui_Spacing(ctx)
                    local waveform_hue_changed, new_waveform_hue = r.ImGui_SliderDouble(ctx, "Waveform Color (Hue)", ui_settings.waveform_hue, 0.0, 1.0, "%.2f")
                    if waveform_hue_changed then
                        ui_settings.waveform_hue = new_waveform_hue
                        save_options()
                    end
                    
                    r.ImGui_Spacing(ctx)
                    local waveform_thickness_changed, new_waveform_thickness = r.ImGui_SliderDouble(ctx, "Waveform Line Thickness", ui_settings.waveform_thickness, 1.0, 5.0, "%.1f")
                    if waveform_thickness_changed then
                        ui_settings.waveform_thickness = new_waveform_thickness
                        save_options()
                    end
                    
                    r.ImGui_Spacing(ctx)
                    local resolution_changed, new_resolution = r.ImGui_SliderDouble(ctx, "Waveform Resolution Detail", ui_settings.waveform_resolution_multiplier, 1.0, 8.0, "%.1fx")
                    if resolution_changed then
                        ui_settings.waveform_resolution_multiplier = new_resolution
                        waveform.cache = {}
                        waveform.cache_file = ""
                        waveform.spectral_cache = {}
                        waveform.spectral_cache_file = ""
                        save_options()
                    end
                    
                    r.ImGui_Spacing(ctx)
                    local accent_hue_changed, new_accent_hue = r.ImGui_SliderDouble(ctx, "Accent Color (Hue)", ui_settings.accent_hue, 0.0, 1.0, "%.2f")
                    if accent_hue_changed then
                        ui_settings.accent_hue = new_accent_hue
                        save_options()
                    end
                    
                    r.ImGui_Spacing(ctx)
                    local selection_hue_changed, new_selection_hue = r.ImGui_SliderDouble(ctx, "Selection Color (Hue)", ui_settings.selection_hue, 0.0, 1.0, "%.2f")
                    if selection_hue_changed then
                        ui_settings.selection_hue = new_selection_hue
                        save_options()
                    end
                    
                    r.ImGui_Spacing(ctx)
                    local selection_sat_changed, new_selection_sat = r.ImGui_SliderDouble(ctx, "Selection Saturation (0=Gray, 1=Color)", ui_settings.selection_saturation, 0.0, 1.0, "%.2f")
                    if selection_sat_changed then
                        ui_settings.selection_saturation = new_selection_sat
                        save_options()
                    end
                    
                    r.ImGui_Spacing(ctx)
                    local button_height_changed, new_button_height = r.ImGui_SliderInt(ctx, "Folder/Collection Button Height", ui_settings.button_height, 15, 50)
                    if button_height_changed then
                        ui_settings.button_height = new_button_height
                        save_options()
                    end
                    
                    r.ImGui_Spacing(ctx)
                    r.ImGui_Spacing(ctx)
                    
                    r.ImGui_Text(ctx, "Font:")
                    r.ImGui_SameLine(ctx)
                    r.ImGui_SetNextItemWidth(ctx, 200)
                    if r.ImGui_BeginCombo(ctx, "##FontSelect", ui_settings.selected_font) then
                        for _, font_name in ipairs(available_fonts) do
                            local is_selected = (ui_settings.selected_font == font_name)
                            if r.ImGui_Selectable(ctx, font_name, is_selected) then
                                ui_settings.selected_font = font_name
                                font_objects = {}
                                update_fonts()
                                save_options()
                            end
                            if is_selected then
                                r.ImGui_SetItemDefaultFocus(ctx)
                            end
                        end
                        r.ImGui_EndCombo(ctx)
                    end
                    
                    r.ImGui_Spacing(ctx)
                    r.ImGui_Spacing(ctx)
                    local waveform_bg_changed, new_waveform_bg = r.ImGui_Checkbox(ctx, "Show Waveform Background", ui_settings.show_waveform_bg)
                    if waveform_bg_changed then
                        ui_settings.show_waveform_bg = new_waveform_bg
                        save_options()
                    end
                    
                    r.ImGui_Spacing(ctx)
                    local scrollbar_changed, new_scrollbar = r.ImGui_Checkbox(ctx, "Hide Scrollbars", ui_settings.hide_scrollbar)
                    if scrollbar_changed then
                        ui_settings.hide_scrollbar = new_scrollbar
                        save_options()
                    end
                    
                    r.ImGui_Spacing(ctx)
                    local numaplayer_changed, new_numaplayer = r.ImGui_Checkbox(ctx, "Use Numa Player for MIDI", ui_settings.use_numaplayer)
                    if numaplayer_changed then
                        ui_settings.use_numaplayer = new_numaplayer
                        save_options()
                    end
                    if r.ImGui_IsItemHovered(ctx) then
                        r.ImGui_SetTooltip(ctx, "Use Numa Player instead of ReaSynth for MIDI playback.\nFalls back to ReaSynth if Numa Player is not installed.\nPreset selection opens automatically on first use.")
                    end
                    
                    r.ImGui_Spacing(ctx)
                    local selected_track_changed, new_selected_track = r.ImGui_Checkbox(ctx, "Use Selected Track for MIDI", ui_settings.use_selected_track_for_midi)
                    if selected_track_changed then
                        ui_settings.use_selected_track_for_midi = new_selected_track
                        save_options()
                    end
                    if r.ImGui_IsItemHovered(ctx) then
                        r.ImGui_SetTooltip(ctx, "Play MIDI files through the currently selected track instead of creating a preview track.\nIf no track is selected, a message will be shown in the MIDI info field.")
                    end
                    
                    r.ImGui_Spacing(ctx)
                    local pitch_detection_changed, new_pitch_detection = r.ImGui_Checkbox(ctx, "Show Pitch Detection", ui.pitch_detection_enabled)
                    if pitch_detection_changed then
                        ui.pitch_detection_enabled = new_pitch_detection
                        save_options()
                    end
                    if r.ImGui_IsItemHovered(ctx) then
                        r.ImGui_SetTooltip(ctx, "Show real-time pitch detection during audio playback in the waveform view.\nDisplays the detected musical note and frequency.")
                    end
                    
                    r.ImGui_Spacing(ctx)
                    r.ImGui_Spacing(ctx)
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), header_color)
                    r.ImGui_SeparatorText(ctx, "Table Columns Visibility")
                    r.ImGui_PopStyleColor(ctx, 1)
                    r.ImGui_Spacing(ctx)
                    
                    r.ImGui_Text(ctx, "Essential:")
                    
                    local ch1, val1 = r.ImGui_Checkbox(ctx, "Name##col", ui_settings.visible_columns.name)
                    if ch1 then ui_settings.visible_columns.name = val1; save_options() end
                    r.ImGui_SameLine(ctx, 200)
                    
                    ch1, val1 = r.ImGui_Checkbox(ctx, "Type##col", ui_settings.visible_columns.type)
                    if ch1 then ui_settings.visible_columns.type = val1; save_options() end
                    r.ImGui_SameLine(ctx, 320)
                    
                    ch1, val1 = r.ImGui_Checkbox(ctx, "Size##col", ui_settings.visible_columns.size)
                    if ch1 then ui_settings.visible_columns.size = val1; save_options() end
                    r.ImGui_SameLine(ctx, 440)
                    
                    ch1, val1 = r.ImGui_Checkbox(ctx, "Duration##col", ui_settings.visible_columns.duration)
                    if ch1 then ui_settings.visible_columns.duration = val1; save_options() end
                    
                    ch1, val1 = r.ImGui_Checkbox(ctx, "Sample Rate##col", ui_settings.visible_columns.sample_rate)
                    if ch1 then ui_settings.visible_columns.sample_rate = val1; save_options() end
                    r.ImGui_SameLine(ctx, 200)
                    
                    ch1, val1 = r.ImGui_Checkbox(ctx, "Channels##col", ui_settings.visible_columns.channels)
                    if ch1 then ui_settings.visible_columns.channels = val1; save_options() end
                    r.ImGui_SameLine(ctx, 320)
                    
                    ch1, val1 = r.ImGui_Checkbox(ctx, "BPM##col", ui_settings.visible_columns.bpm)
                    if ch1 then ui_settings.visible_columns.bpm = val1; save_options() end
                    r.ImGui_SameLine(ctx, 440)
                    
                    ch1, val1 = r.ImGui_Checkbox(ctx, "Key##col", ui_settings.visible_columns.key)
                    if ch1 then ui_settings.visible_columns.key = val1; save_options() end
                    
                    r.ImGui_Spacing(ctx)
                    r.ImGui_Separator(ctx)
                    r.ImGui_Spacing(ctx)
                    
                    r.ImGui_Text(ctx, "Music Metadata:")
                    
                    ch1, val1 = r.ImGui_Checkbox(ctx, "Artist##col", ui_settings.visible_columns.artist)
                    if ch1 then ui_settings.visible_columns.artist = val1; save_options() end
                    r.ImGui_SameLine(ctx, 200)
                    
                    ch1, val1 = r.ImGui_Checkbox(ctx, "Album##col", ui_settings.visible_columns.album)
                    if ch1 then ui_settings.visible_columns.album = val1; save_options() end
                    r.ImGui_SameLine(ctx, 320)
                    
                    ch1, val1 = r.ImGui_Checkbox(ctx, "Title##col", ui_settings.visible_columns.title)
                    if ch1 then ui_settings.visible_columns.title = val1; save_options() end
                    r.ImGui_SameLine(ctx, 440)
                    
                    ch1, val1 = r.ImGui_Checkbox(ctx, "Track##col", ui_settings.visible_columns.track)
                    if ch1 then ui_settings.visible_columns.track = val1; save_options() end
                    
                    ch1, val1 = r.ImGui_Checkbox(ctx, "Year##col", ui_settings.visible_columns.year)
                    if ch1 then ui_settings.visible_columns.year = val1; save_options() end
                    r.ImGui_SameLine(ctx, 200)
                    
                    ch1, val1 = r.ImGui_Checkbox(ctx, "Genre##col", ui_settings.visible_columns.genre)
                    if ch1 then ui_settings.visible_columns.genre = val1; save_options() end
                    r.ImGui_SameLine(ctx, 320)
                    
                    ch1, val1 = r.ImGui_Checkbox(ctx, "Comment##col", ui_settings.visible_columns.comment)
                    if ch1 then ui_settings.visible_columns.comment = val1; save_options() end
                    r.ImGui_SameLine(ctx, 440)
                    
                    ch1, val1 = r.ImGui_Checkbox(ctx, "Composer##col", ui_settings.visible_columns.composer)
                    if ch1 then ui_settings.visible_columns.composer = val1; save_options() end
                    
                    ch1, val1 = r.ImGui_Checkbox(ctx, "Publisher##col", ui_settings.visible_columns.publisher)
                    if ch1 then ui_settings.visible_columns.publisher = val1; save_options() end
                    r.ImGui_SameLine(ctx, 200)
                    
                    ch1, val1 = r.ImGui_Checkbox(ctx, "Time Signature##col", ui_settings.visible_columns.timesignature)
                    if ch1 then ui_settings.visible_columns.timesignature = val1; save_options() end
                    
                    r.ImGui_Spacing(ctx)
                    r.ImGui_Separator(ctx)
                    r.ImGui_Spacing(ctx)
                    
                    r.ImGui_Text(ctx, "Technical Metadata:")
                    
                    ch1, val1 = r.ImGui_Checkbox(ctx, "Bitrate##col", ui_settings.visible_columns.bitrate)
                    if ch1 then ui_settings.visible_columns.bitrate = val1; save_options() end
                    r.ImGui_SameLine(ctx, 200)
                    
                    ch1, val1 = r.ImGui_Checkbox(ctx, "Bit Depth##col", ui_settings.visible_columns.bitspersample)
                    if ch1 then ui_settings.visible_columns.bitspersample = val1; save_options() end
                    r.ImGui_SameLine(ctx, 320)
                    
                    ch1, val1 = r.ImGui_Checkbox(ctx, "Encoder##col", ui_settings.visible_columns.encoder)
                    if ch1 then ui_settings.visible_columns.encoder = val1; save_options() end
                    r.ImGui_SameLine(ctx, 440)
                    
                    ch1, val1 = r.ImGui_Checkbox(ctx, "Copyright##col", ui_settings.visible_columns.copyright)
                    if ch1 then ui_settings.visible_columns.copyright = val1; save_options() end
                    
                    r.ImGui_Spacing(ctx)
                    r.ImGui_Separator(ctx)
                    r.ImGui_Spacing(ctx)
                    
                    r.ImGui_Text(ctx, "BWF Metadata:")
                    
                    ch1, val1 = r.ImGui_Checkbox(ctx, "Description##col", ui_settings.visible_columns.desc)
                    if ch1 then ui_settings.visible_columns.desc = val1; save_options() end
                    r.ImGui_SameLine(ctx, 200)
                    
                    ch1, val1 = r.ImGui_Checkbox(ctx, "Originator##col", ui_settings.visible_columns.originator)
                    if ch1 then ui_settings.visible_columns.originator = val1; save_options() end
                    r.ImGui_SameLine(ctx, 320)
                    
                    ch1, val1 = r.ImGui_Checkbox(ctx, "Orig Ref##col", ui_settings.visible_columns.originatorref)
                    if ch1 then ui_settings.visible_columns.originatorref = val1; save_options() end
                    r.ImGui_SameLine(ctx, 440)
                    
                    ch1, val1 = r.ImGui_Checkbox(ctx, "Date##col", ui_settings.visible_columns.date)
                    if ch1 then ui_settings.visible_columns.date = val1; save_options() end
                    
                    ch1, val1 = r.ImGui_Checkbox(ctx, "Time##col", ui_settings.visible_columns.time)
                    if ch1 then ui_settings.visible_columns.time = val1; save_options() end
                    r.ImGui_SameLine(ctx, 200)
                    
                    ch1, val1 = r.ImGui_Checkbox(ctx, "UMID##col", ui_settings.visible_columns.umid)
                    if ch1 then ui_settings.visible_columns.umid = val1; save_options() end
                    
                    r.ImGui_Spacing(ctx)
                    r.ImGui_Spacing(ctx)
                    r.ImGui_Separator(ctx)
                    r.ImGui_Spacing(ctx)
                    
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xFF4444FF)
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xFF6666FF)
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xFF8888FF)
                    if r.ImGui_Button(ctx, "Reset to Default Settings", -1, 0) then
                        ui_settings.window_bg_brightness = 0.12
                        ui_settings.window_opacity = 0.94
                        ui_settings.text_brightness = 1.0
                        ui_settings.grid_brightness = 1.0
                        ui_settings.button_brightness = 0.25
                        ui_settings.button_text_brightness = 1.0
                        ui_settings.waveform_hue = 0.55
                        ui_settings.waveform_thickness = 1.0
                        ui_settings.waveform_resolution_multiplier = 2.0
                        ui_settings.accent_hue = 0.55
                        ui_settings.selection_hue = 0.16
                        ui_settings.selection_saturation = 1.0
                        ui_settings.show_waveform_bg = true
                        ui_settings.hide_scrollbar = false
                        ui_settings.button_height = 25
                        ui_settings.selected_font = "Arial"
                        font_objects = {}  
                        update_fonts()  
                        save_options()
                    end
                    r.ImGui_PopStyleColor(ctx, 3)
                    
                    r.ImGui_PopStyleColor(ctx, 9)
                    r.ImGui_PopStyleVar(ctx, 2)
                elseif ui.current_view_mode == "shortcuts" then
                    -- Keyboard Shortcuts Panel
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), hsv_to_color(ui_settings.accent_hue))
                    r.ImGui_Text(ctx, "KEYBOARD SHORTCUTS")
                    r.ImGui_PopStyleColor(ctx, 1)
                    r.ImGui_Spacing(ctx)
                    r.ImGui_Spacing(ctx)
                    
                    -- Playback Controls
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), hsv_to_color(ui_settings.accent_hue, 1.0, 0.8))
                    r.ImGui_Text(ctx, "PLAYBACK")
                    r.ImGui_PopStyleColor(ctx, 1)
                    r.ImGui_Spacing(ctx)
                    r.ImGui_BulletText(ctx, "Enter/Return       Play File (no pause)")
                    r.ImGui_BulletText(ctx, "Double-Click       Insert at Edit Cursor")
                    r.ImGui_BulletText(ctx, "Click Waveform     Seek to Position")
                    r.ImGui_BulletText(ctx, "Drag Waveform      Create Time Selection")
                    r.ImGui_Spacing(ctx)
                    r.ImGui_Spacing(ctx)
                    
                    -- Zoom & Navigation
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), hsv_to_color(ui_settings.accent_hue, 1.0, 0.8))
                    r.ImGui_Text(ctx, "ZOOM & NAVIGATION")
                    r.ImGui_PopStyleColor(ctx, 1)
                    r.ImGui_Spacing(ctx)
                    r.ImGui_BulletText(ctx, "Ctrl+Wheel         Horizontal Zoom (1x-8x)")
                    r.ImGui_BulletText(ctx, "Ctrl+Alt+Wheel     Vertical Zoom (0.5x-10x)")
                    r.ImGui_BulletText(ctx, "Wheel              Horizontal Scroll (when zoomed)")
                    r.ImGui_BulletText(ctx, "RESET Button       Reset All Zoom (visible when zoomed)")
                    r.ImGui_Spacing(ctx)
                    r.ImGui_Spacing(ctx)
                    
                    -- Navigation
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), hsv_to_color(ui_settings.accent_hue, 1.0, 0.8))
                    r.ImGui_Text(ctx, "NAVIGATION")
                    r.ImGui_PopStyleColor(ctx, 1)
                    r.ImGui_Spacing(ctx)
                    r.ImGui_BulletText(ctx, "Up/Down Arrow      Navigate File List")
                    r.ImGui_BulletText(ctx, "Page Up/Down       Jump Multiple Files")
                    r.ImGui_BulletText(ctx, "Home/End           First/Last File")
                    r.ImGui_BulletText(ctx, "Click              Select File")
                    r.ImGui_BulletText(ctx, "Shift+Click        Range Selection")
                    r.ImGui_BulletText(ctx, "Ctrl+Click         Multi-Selection")
                    r.ImGui_BulletText(ctx, "Right-Click        Context Menu")
                    r.ImGui_BulletText(ctx, "Enter              Open/Close Folder (Tree View)")
                    r.ImGui_BulletText(ctx, "Left Arrow         Close Tree Node")
                    r.ImGui_BulletText(ctx, "Right Arrow        Open Tree Node")
                    r.ImGui_Spacing(ctx)
                    r.ImGui_Spacing(ctx)
                    
                    -- View Options
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), hsv_to_color(ui_settings.accent_hue, 1.0, 0.8))
                    r.ImGui_Text(ctx, "VIEW OPTIONS")
                    r.ImGui_PopStyleColor(ctx, 1)
                    r.ImGui_Spacing(ctx)
                    r.ImGui_BulletText(ctx, "SPECTRAL Button    Toggle FFT Frequency Analysis")
                    r.ImGui_BulletText(ctx, "GRID Button        Toggle Time Grid Overlay")
                    r.ImGui_BulletText(ctx, "SOLO Button        Solo Selected File (others hidden)")
                    r.ImGui_Spacing(ctx)
                    r.ImGui_Spacing(ctx)
                    
                    -- Waveform Features
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), hsv_to_color(ui_settings.accent_hue, 1.0, 0.8))
                    r.ImGui_Text(ctx, "WAVEFORM FEATURES")
                    r.ImGui_PopStyleColor(ctx, 1)
                    r.ImGui_Spacing(ctx)
                    r.ImGui_BulletText(ctx, "Spectral Colors:   Red=Bass, Orange=Low-Mid, Green=Mid,")
                    r.ImGui_Text(ctx, "                   Blue=High-Mid, Purple=High")
                    r.ImGui_BulletText(ctx, "Zoom Indicators:   H: Xx (horizontal), V: X.Xx (vertical)")
                    r.ImGui_BulletText(ctx, "Resolution:        Adjust in Settings (1x-8x detail)")
                    r.ImGui_Spacing(ctx)
                    r.ImGui_Spacing(ctx)
                    
                    -- Settings & Presets
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), hsv_to_color(ui_settings.accent_hue, 1.0, 0.8))
                    r.ImGui_Text(ctx, "SETTINGS & PRESETS")
                    r.ImGui_PopStyleColor(ctx, 1)
                    r.ImGui_Spacing(ctx)
                    r.ImGui_BulletText(ctx, "Settings Icon      Access All Visual Settings")
                    r.ImGui_BulletText(ctx, "Save Preset        Store Current Settings to JSON")
                    r.ImGui_BulletText(ctx, "Load Preset        Restore Saved Settings")
                    r.ImGui_BulletText(ctx, "Delete Preset      Remove Saved Preset")
                    
                elseif ui.current_view_mode == "folders" or ui.current_view_mode == "collections" then
                    draw_file_list()
                end
            end
            r.ImGui_EndChild(ctx)
            
            if scrollbar_pushed then
                r.ImGui_PopStyleVar(ctx, 1)
            end
            
            r.ImGui_Separator(ctx)
            local footer_width = r.ImGui_GetContentRegionAvail(ctx)
            local footer_height = 92
            local ruler_height = 15
            local waveform_height = footer_height - ruler_height
            local draw_list = r.ImGui_GetWindowDrawList(ctx)
            local footer_x, footer_y = r.ImGui_GetCursorScreenPos(ctx)
            if ui_settings.show_waveform_bg then
                r.ImGui_DrawList_AddRectFilled(draw_list, footer_x, footer_y, footer_x + footer_width, footer_y + footer_height, 0x00000055)
                r.ImGui_DrawList_AddRect(draw_list, footer_x, footer_y, footer_x + footer_width, footer_y + footer_height, 0xFFFFFF33, 0, 0, 1)
            end
            local ruler_y = footer_y
            local waveform_y = footer_y + ruler_height
            local ruler_bg_color = r.ImGui_ColorConvertDouble4ToU32(
                ui_settings.window_bg_brightness * 0.8,
                ui_settings.window_bg_brightness * 0.8,
                ui_settings.window_bg_brightness * 0.8,
                1.0
            )
            r.ImGui_DrawList_AddRectFilled(draw_list, footer_x, ruler_y, footer_x + footer_width, ruler_y + ruler_height, ruler_bg_color)
            local file_to_show = playback.current_playing_file ~= "" and playback.current_playing_file or (playback.last_displayed_file ~= "" and playback.last_displayed_file or (ui.selected_index > 0 and ui.visible_files[ui.selected_index] and ui.visible_files[ui.selected_index].path))
            if file_to_show and file_to_show ~= "" then
                local length = get_cached_file_length(file_to_show)
                if length > 0 then
                        local visible_duration = length / waveform.zoom_level
                        local max_scroll_time = math.max(0, length - visible_duration)
                        local scroll_time_offset = waveform.scroll_offset * max_scroll_time
                        local visible_start_time = scroll_time_offset
                        local visible_end_time = scroll_time_offset + visible_duration
                        
                        local num_main_ticks = math.max(4, math.floor(footer_width / 80))
                        local num_subticks_per_interval = 4
                        
                        local main_tick_positions = {}
                        for i = 0, num_main_ticks do
                            local progress = i / num_main_ticks
                            local x = footer_x + (progress * footer_width)
                            main_tick_positions[i] = x
                        end
                        
                        for i = 0, num_main_ticks - 1 do
                            local start_x = main_tick_positions[i]
                            local end_x = main_tick_positions[i+1]
                            local interval = end_x - start_x
                            for j = 1, num_subticks_per_interval do
                                local sub_x = start_x + (j * interval / (num_subticks_per_interval + 1))
                                local sub_tick_color = r.ImGui_ColorConvertDouble4ToU32(
                                    ui_settings.grid_brightness,
                                    ui_settings.grid_brightness,
                                    ui_settings.grid_brightness,
                                    0.13
                                )
                                r.ImGui_DrawList_AddLine(draw_list, sub_x, ruler_y + ruler_height - 2, sub_x, ruler_y + ruler_height, sub_tick_color, 1)
                            end
                        end
                        
                        for i = 0, num_main_ticks do
                            local x = main_tick_positions[i]
                            local progress = i / num_main_ticks
                            local playrate = playback.effective_playrate or 1.0
                            if playrate == 0 or playrate ~= playrate then 
                                playrate = 1.0
                            end
                            local time = (visible_start_time + progress * visible_duration) / playrate
                            if time ~= time or time == math.huge or time == -math.huge then  
                                time = 0
                            end
                            local tick_height = 6
                            local main_tick_color = r.ImGui_ColorConvertDouble4ToU32(
                                ui_settings.grid_brightness,
                                ui_settings.grid_brightness,
                                ui_settings.grid_brightness,
                                0.67
                            )
                            r.ImGui_DrawList_AddLine(draw_list, x, ruler_y + ruler_height - tick_height, x, ruler_y + ruler_height, main_tick_color, 1.5)
                            local time_text
                            local mins = math.floor(time / 60)
                            local secs = math.floor(time % 60)
                            local ms = math.floor((time % 1) * 1000)
                            mins = (mins ~= mins or mins == math.huge or mins == -math.huge) and 0 or mins
                            secs = (secs ~= secs or secs == math.huge or secs == -math.huge) and 0 or secs
                            ms = (ms ~= ms or ms == math.huge or ms == -math.huge) and 0 or ms
                            time_text = string.format("%d:%02d:%03d", mins, secs, ms)
                            r.ImGui_PushFont(ctx, small_font, small_font_size)
                            local text_w, text_h = r.ImGui_CalcTextSize(ctx, time_text)
                            local text_x = x - text_w / 2
                            if i == 0 then
                                text_x = x + 2
                            elseif i == num_main_ticks then
                                text_x = x - text_w - 2
                            end
                            local ruler_text_color = r.ImGui_ColorConvertDouble4ToU32(
                                ui_settings.text_brightness,
                                ui_settings.text_brightness,
                                ui_settings.text_brightness,
                                0.8
                            )
                            r.ImGui_DrawList_AddText(draw_list, text_x, ruler_y + 2, ruler_text_color, time_text)
                            r.ImGui_PopFont(ctx)
                        end
                    end
                end
            local center_y = waveform_y + waveform_height / 2
            r.ImGui_DrawList_AddLine(draw_list, footer_x, center_y, footer_x + footer_width, center_y, 0x444444FF, 1)
            local file_to_show = playback.current_playing_file ~= "" and playback.current_playing_file or (playback.last_displayed_file ~= "" and playback.last_displayed_file or (ui.selected_index > 0 and ui.visible_files[ui.selected_index] and ui.visible_files[ui.selected_index].path))
            if file_to_show and file_to_show ~= "" then
                local is_midi = file_to_show:lower():match("%.mid$") or file_to_show:lower():match("%.midi$")
                local ext = file_to_show:match("%.([^%.]+)$")
                local is_video_or_gif = false
                if ext then
                    ext = ext:lower()
                    local video_extensions = {
                        mp4 = true, mov = true, avi = true, mkv = true, wmv = true,
                        flv = true, webm = true, m4v = true, mpg = true, mpeg = true,
                        gif = true
                    }
                    is_video_or_gif = video_extensions[ext] or false
                end
                
                local pixels = math.floor(footer_width * ui_settings.waveform_resolution_multiplier)
                if is_midi then
                    if waveform.midi_notes_file ~= file_to_show or #waveform.midi_notes == 0 then
                        waveform.midi_notes, waveform.midi_length = load_midi_notes(file_to_show)
                        waveform.midi_notes_file = file_to_show
                    end
                    
                    if #waveform.midi_notes > 0 then
                        local length = get_cached_file_length(file_to_show)
                        if length > 0 then
                            local midi_color = hsv_to_color(ui_settings.accent_hue, 1.0, 1.0, 1.0)
                            for _, note in ipairs(waveform.midi_notes) do
                                local start_x = footer_x + (note.start / length) * footer_width
                                local end_x = footer_x + (note.end_time / length) * footer_width
                                local note_y = center_y - ((note.pitch - 60) / 24) * (waveform_height * 0.4)  
                                local note_height = 3  
                                r.ImGui_DrawList_AddRectFilled(draw_list, start_x, note_y - note_height/2, end_x, note_y + note_height/2, midi_color)
                            end
                        end
                    end
                elseif not is_video_or_gif and (waveform.cache_file ~= file_to_show or #waveform.cache ~= pixels) then
                    waveform.cache = {}
                    waveform.cache_file = file_to_show
                    local temp_track = r.GetTrack(0, 0)
                    if temp_track then
                        local num_items_before = r.CountTrackMediaItems(temp_track)
                        local temp_item = r.AddMediaItemToTrack(temp_track)
                        if temp_item then
                            local take = r.AddTakeToMediaItem(temp_item)
                            if take then
                                local source = r.PCM_Source_CreateFromFile(file_to_show)
                                r.SetMediaItemTake_Source(take, source)
                                local length = r.GetMediaSourceLength(source)
                                if length and length > 0 then
                                    r.SetMediaItemLength(temp_item, length, false)
                                    r.UpdateItemInProject(temp_item)
                                    local accessor = r.CreateTakeAudioAccessor(take)
                                    if accessor then
                                        local samplerate = 44100
                                        local numch = r.GetMediaSourceNumChannels(source) or 2
                                        for i = 0, pixels - 1 do
                                            local start_time = (i / pixels) * length
                                            local samples_to_read = math.max(100, math.floor((length / pixels) * samplerate))
                                            local buffer = r.new_array(samples_to_read * numch)
                                            local ok = r.GetAudioAccessorSamples(accessor, samplerate, numch, start_time, samples_to_read, buffer)
                                            local peak = 0
                                            if ok > 0 then
                                                for j = 1, ok * numch do
                                                    local v = math.abs(buffer[j] or 0)
                                                    if v > peak then peak = v end
                                                end
                                            end
                                            waveform.cache[i + 1] = peak
                                            buffer.clear()
                                        end
                                        r.DestroyAudioAccessor(accessor)
                                    end
                                end
                            end
                            r.DeleteTrackMediaItem(temp_track, temp_item)
                        end
                    end
                end
                if not is_midi and #waveform.cache > 0 then
                    if waveform.show_spectral_view then
                        if waveform.spectral_cache_file ~= file_to_show or #waveform.spectral_cache ~= pixels then
                            waveform.spectral_cache = calculate_spectral_data(file_to_show, pixels, 1)
                            waveform.spectral_cache_file = file_to_show
                        end
                        
                        if #waveform.spectral_cache > 0 then
                            local total_samples = #waveform.cache
                            local visible_samples = math.floor(total_samples / waveform.zoom_level)
                            local max_scroll = math.max(0, total_samples - visible_samples)
                            local scroll_sample_offset = math.floor(waveform.scroll_offset * max_scroll)
                            
                            for i = 1, visible_samples do
                                local cache_index = scroll_sample_offset + i
                                if cache_index >= 1 and cache_index <= total_samples then
                                    local peak = waveform.cache[cache_index] * waveform.vertical_zoom
                                    peak = math.min(peak, 1.0)  
                                    local x = footer_x + (i - 1) * (footer_width / visible_samples)
                                    local y_top = center_y - (peak * waveform_height * 0.45)
                                    local y_bottom = center_y + (peak * waveform_height * 0.45)
                                    
                                    local spectral_index = math.floor((cache_index / #waveform.cache) * #waveform.spectral_cache) + 1
                                    spectral_index = math.min(spectral_index, #waveform.spectral_cache)
                                    local zcr_value = waveform.spectral_cache[spectral_index] or 0.5
                                
                                local red, green, blue
                                
                                if zcr_value < 0.25 then
                                    local t = zcr_value / 0.25
                                    red = 255
                                    green = 51 + (119 * t)
                                    blue = 0
                                elseif zcr_value < 0.50 then
                                    local t = (zcr_value - 0.25) / 0.25
                                    red = 255 - (204 * t)
                                    green = 170 + (34 * t)
                                    blue = 0 + (51 * t)
                                elseif zcr_value < 0.75 then
                                    local t = (zcr_value - 0.50) / 0.25
                                    red = 51
                                    green = 204 - (51 * t)
                                    blue = 51 + (204 * t)
                                else
                                    local t = (zcr_value - 0.75) / 0.25
                                    red = 51 + (119 * t)
                                    green = 153 - (102 * t)
                                    blue = 255
                                end
                                
                                    local color = r.ImGui_ColorConvertDouble4ToU32(red/255, green/255, blue/255, 1.0)
                                    r.ImGui_DrawList_AddLine(draw_list, x, y_top, x, y_bottom, color, ui_settings.waveform_thickness)
                                end
                            end
                        end
                    else
                        local h = ui_settings.waveform_hue
                        local s = 1.0
                        local v = 1.0
                        
                        local red, green, blue
                        local i = math.floor(h * 6)
                        local f = h * 6 - i
                        local p = v * (1 - s)
                        local q = v * (1 - f * s)
                        local t = v * (1 - (1 - f) * s)
                        
                        i = i % 6
                        if i == 0 then red, green, blue = v, t, p
                        elseif i == 1 then red, green, blue = q, v, p
                        elseif i == 2 then red, green, blue = p, v, t
                        elseif i == 3 then red, green, blue = p, q, v
                        elseif i == 4 then red, green, blue = t, p, v
                        else red, green, blue = v, p, q
                        end
                        
                        local waveform_color = r.ImGui_ColorConvertDouble4ToU32(red, green, blue, 1.0)
                        
                        local total_samples = #waveform.cache
                        local visible_samples = math.floor(total_samples / waveform.zoom_level)
                        local max_scroll = math.max(0, total_samples - visible_samples)
                        local scroll_sample_offset = math.floor(waveform.scroll_offset * max_scroll)
                        
                        for i = 1, visible_samples do
                            local cache_index = scroll_sample_offset + i
                            if cache_index >= 1 and cache_index <= total_samples then
                                local peak = waveform.cache[cache_index] * waveform.vertical_zoom
                                peak = math.min(peak, 1.0)  
                                local x = footer_x + (i - 1) * (footer_width / visible_samples)
                                local y_top = center_y - (peak * waveform_height * 0.45)
                                local y_bottom = center_y + (peak * waveform_height * 0.45)
                                r.ImGui_DrawList_AddLine(draw_list, x, y_top, x, y_bottom, waveform_color, ui_settings.waveform_thickness)
                            end
                        end
                    end
                end
                if file_to_show and file_to_show == playback.current_playing_file then
                    local length = get_file_display_length(file_to_show)
                    if length > 0 then
                            local play_pos = 0
                            if playback.playing_preview then
                                local retval, pos = r.CF_Preview_GetValue(playback.playing_preview, "D_POSITION")
                                play_pos = pos or 0
                            elseif playback.is_midi_playback then
                                play_pos = r.GetPlayPosition()
                            elseif playback.is_paused and playback.paused_position then
                                play_pos = playback.paused_position
                            end
                            local adjusted_length = length / (playback.effective_playrate or 1.0)
                            local progress = math.min(play_pos / adjusted_length, 1)
                            
                            local visible_duration = 1.0 / waveform.zoom_level
                            local max_scroll = math.max(0, 1.0 - visible_duration)
                            local visible_start = waveform.scroll_offset * max_scroll
                            local visible_end = visible_start + visible_duration
                            
                            if progress >= visible_start and progress <= visible_end then
                                local visible_progress = (progress - visible_start) / visible_duration
                                local cursor_x = footer_x + (visible_progress * footer_width)
                                r.ImGui_DrawList_AddLine(draw_list, cursor_x, footer_y, cursor_x, footer_y + footer_height, 0xFFFF00FF, 2)
                            end
                    end
                end
                if waveform.selection_active and waveform.selection_start ~= waveform.selection_end then
                    local visible_duration = 1.0 / waveform.zoom_level
                    local max_scroll = math.max(0, 1.0 - visible_duration)
                    local visible_start = waveform.scroll_offset * max_scroll
                    local visible_end = visible_start + visible_duration
                    
                    local sel_start = math.min(waveform.selection_start, waveform.selection_end)
                    local sel_end = math.max(waveform.selection_start, waveform.selection_end)
                    
                    if sel_end >= visible_start and sel_start <= visible_end then
                        local visible_sel_start = math.max(sel_start, visible_start)
                        local visible_sel_end = math.min(sel_end, visible_end)
                        
                        local visible_start_progress = (visible_sel_start - visible_start) / visible_duration
                        local visible_end_progress = (visible_sel_end - visible_start) / visible_duration
                        
                        local sel_start_x = footer_x + (visible_start_progress * footer_width)
                        local sel_end_x = footer_x + (visible_end_progress * footer_width)
                        
                        local selection_color = hsv_to_color(ui_settings.selection_hue, ui_settings.selection_saturation, 1.0, 0.2)
                        r.ImGui_DrawList_AddRectFilled(draw_list, sel_start_x, waveform_y, sel_end_x, footer_y + footer_height, selection_color)
                    end
                end
                
                if playback.selected_file ~= "" or playback.current_playing_file ~= "" then
                    local visible_duration = 1.0 / waveform.zoom_level
                    local max_scroll = math.max(0, 1.0 - visible_duration)
                    local visible_start = waveform.scroll_offset * max_scroll
                    local visible_end = visible_start + visible_duration
                    
                    if waveform.play_cursor_position >= visible_start and waveform.play_cursor_position <= visible_end then
                        local visible_progress = (waveform.play_cursor_position - visible_start) / visible_duration
                        local cursor_x = footer_x + (visible_progress * footer_width)
                        local play_cursor_color = hsv_to_color(ui_settings.accent_hue, 1.0, 1.0, 1.0)
                        r.ImGui_DrawList_AddLine(draw_list, cursor_x, waveform_y, cursor_x, footer_y + footer_height, play_cursor_color, 2)
                    end
                end
            else
                waveform.cache = {}
                waveform.cache_file = ""
                waveform.oscilloscope_cache = {}
                waveform.oscilloscope_cache_file = ""
                waveform.spectral_cache = {}
                waveform.spectral_cache_file = ""
                waveform.midi_notes = {}
                waveform.midi_notes_file = ""
                waveform.midi_length = 0
                waveform.selection_active = false
                local text = "WAVEFORM"
                local text_size_w, text_size_h = r.ImGui_CalcTextSize(ctx, text)
                local text_x = footer_x + (footer_width - text_size_w) / 2
                local text_y = footer_y + (footer_height - text_size_h) / 2
                r.ImGui_DrawList_AddText(draw_list, text_x, text_y, 0x888888FF, text)
            end
            
            if ui.waveform_grid_overlay and footer_x and file_to_show and file_to_show ~= "" then
                local length = get_file_display_length(file_to_show)
                if length > 0 then
                        local grid_color = r.ImGui_ColorConvertDouble4ToU32(
                            ui_settings.grid_brightness,
                            ui_settings.grid_brightness,
                            ui_settings.grid_brightness,
                            0.27
                        )
                        local sub_color = r.ImGui_ColorConvertDouble4ToU32(
                            ui_settings.grid_brightness,
                            ui_settings.grid_brightness,
                            ui_settings.grid_brightness,
                            0.13
                        )
                        
                        local num_main_ticks = math.max(4, math.floor(footer_width / 80))
                        local num_subticks_per_interval = 4
                        
                        local ruler_positions = {}
                        for i = 0, num_main_ticks do
                            local progress = i / num_main_ticks
                            local x = footer_x + (progress * footer_width)
                            ruler_positions[x] = "main"
                        end
                        for i = 0, num_main_ticks - 1 do
                            local start_x = footer_x + (i * footer_width / num_main_ticks)
                            local end_x = footer_x + ((i + 1) * footer_width / num_main_ticks)
                            local interval = end_x - start_x
                            for j = 1, num_subticks_per_interval do
                                local sub_x = start_x + (j * interval / (num_subticks_per_interval + 1))
                                ruler_positions[sub_x] = "sub"
                            end
                        end
                        
                        local draw_list = r.ImGui_GetWindowDrawList(ctx)
                        local waveform_y = footer_y + 15
                        
                        for x, tick_type in pairs(ruler_positions) do
                            local color = (tick_type == "main") and grid_color or sub_color
                            r.ImGui_DrawList_AddLine(draw_list, x, waveform_y, x, footer_y + footer_height, color, 1)
                        end
                        
                        local center_y = waveform_y + (footer_height - 15) / 2
                        r.ImGui_DrawList_AddLine(draw_list, footer_x, center_y, footer_x + footer_width, center_y, grid_color, 1)
                end
            end
            
            r.ImGui_SetCursorScreenPos(ctx, footer_x, footer_y)
            r.ImGui_InvisibleButton(ctx, "##waveform_interaction", footer_width, footer_height)
            
            local accent_color = hsv_to_color(ui_settings.accent_hue)
            local text_color = r.ImGui_ColorConvertDouble4ToU32(ui_settings.text_brightness, ui_settings.text_brightness, ui_settings.text_brightness, 1.0)
            
            local current_file = playback.current_playing_file ~= "" and playback.current_playing_file or 
                                (ui.selected_index > 0 and ui.visible_files[ui.selected_index] and ui.visible_files[ui.selected_index].path)
            local is_midi_or_video = false
            if current_file then
                local ext = current_file:match("%.([^%.]+)$")
                if ext then
                    ext = ext:lower()
                    is_midi_or_video = ext == "mid" or ext == "midi" or ext == "mp4" or ext == "avi" or ext == "mov" or ext == "mkv" or ext == "webm" or ext == "flv" or ext == "wmv"
                end
            end
            
            local solo_hovered = false
            local spectral_hovered = false
            
            if is_midi_or_video then
                local solo_text = "SOLO"
                local solo_color = playback.use_exclusive_solo and accent_color or text_color
                local solo_w, solo_h = r.ImGui_CalcTextSize(ctx, solo_text)
                local solo_x = footer_x + footer_width - solo_w - 50  
                local solo_y = footer_y + footer_height - solo_h - 2  
                
                r.ImGui_DrawList_AddText(draw_list, solo_x, solo_y, solo_color, solo_text)
                
                local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx)
                solo_hovered = mouse_x >= solo_x - 4 and mouse_x <= solo_x + solo_w + 4 and 
                                     mouse_y >= solo_y - 4 and mouse_y <= solo_y + solo_h + 4
                if solo_hovered and r.ImGui_IsMouseClicked(ctx, 0) then
                    playback.use_exclusive_solo = not playback.use_exclusive_solo
                    save_options()
                    
                    local track_count = r.CountTracks(0)
                    
                    if playback.use_exclusive_solo then
                        playback.saved_solo_states = {}
                        for i = 0, track_count - 1 do
                            local track = r.GetTrack(0, i)
                            local is_preview_track = (playback.video_preview_track and track == playback.video_preview_track)
                            if not is_preview_track then
                                local solo_state = r.GetMediaTrackInfo_Value(track, "I_SOLO")
                                playback.saved_solo_states[i] = solo_state
                                r.SetMediaTrackInfo_Value(track, "I_SOLO", 0)
                            end
                        end
                        if playback.video_preview_track then
                            r.SetMediaTrackInfo_Value(playback.video_preview_track, "I_SOLO", 1)
                        end
                    else
                        for track_idx, solo_state in pairs(playback.saved_solo_states) do
                            local track = r.GetTrack(0, track_idx)
                            if track then
                                r.SetMediaTrackInfo_Value(track, "I_SOLO", solo_state)
                            end
                        end
                        playback.saved_solo_states = {}
                        if playback.video_preview_track then
                            r.SetMediaTrackInfo_Value(playback.video_preview_track, "I_SOLO", 0)
                        end
                    end
                end
            end
            
            local is_audio_file = current_file and not is_video_or_image_file(current_file) and not is_midi_or_video
            if is_audio_file then
                local spectral_text = "SPECTRAL"
                local spectral_color = waveform.show_spectral_view and accent_color or text_color
                local spectral_w, spectral_h = r.ImGui_CalcTextSize(ctx, spectral_text)
                local spectral_x = footer_x + footer_width - spectral_w - 55  
                local spectral_y = footer_y + footer_height - spectral_h - 2 
                
                r.ImGui_DrawList_AddText(draw_list, spectral_x, spectral_y, spectral_color, spectral_text)
                
                local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx)
                spectral_hovered = mouse_x >= spectral_x - 4 and mouse_x <= spectral_x + spectral_w + 4 and 
                                   mouse_y >= spectral_y - 4 and mouse_y <= spectral_y + spectral_h + 4
                if spectral_hovered and r.ImGui_IsMouseClicked(ctx, 0) then
                    waveform.show_spectral_view = not waveform.show_spectral_view
                    save_options()
                    waveform.spectral_cache = {}
                    waveform.spectral_cache_file = ""
                end
            end
            
            local grid_text = "GRID"
            local grid_color = ui.waveform_grid_overlay and accent_color or text_color
            local grid_w, grid_h = r.ImGui_CalcTextSize(ctx, grid_text)
            local grid_x = footer_x + footer_width - grid_w - 5
            local grid_y = footer_y + footer_height - grid_h - 2  
            
            r.ImGui_DrawList_AddText(draw_list, grid_x, grid_y, grid_color, grid_text)
            
            local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx)
            local grid_hovered = mouse_x >= grid_x - 4 and mouse_x <= grid_x + grid_w + 4 and 
                                 mouse_y >= grid_y - 4 and mouse_y <= grid_y + grid_h + 4
            if grid_hovered and r.ImGui_IsMouseClicked(ctx, 0) then
                ui.waveform_grid_overlay = not ui.waveform_grid_overlay
                save_options()
            end
            
            local reset_hovered = false
            if is_audio_file and (waveform.zoom_level > 1.0 or waveform.vertical_zoom ~= 1.0) then
                local reset_text = "RESET"
                local reset_color = text_color
                local reset_w, reset_h = r.ImGui_CalcTextSize(ctx, reset_text)
                local reset_x = footer_x + 5  
                local reset_y = footer_y + footer_height - reset_h - 2 
                
                r.ImGui_DrawList_AddText(draw_list, reset_x, reset_y, reset_color, reset_text)
                
                local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx)
                reset_hovered = mouse_x >= reset_x - 4 and mouse_x <= reset_x + reset_w + 4 and 
                                mouse_y >= reset_y - 4 and mouse_y <= reset_y + reset_h + 4
                if reset_hovered and r.ImGui_IsMouseClicked(ctx, 0) then
                    waveform.zoom_level = 1.0
                    waveform.scroll_offset = 0.0
                    waveform.vertical_zoom = 1.0
                end
            end
            
            if is_audio_file then
                local y_offset = footer_y + 20  
                
                if waveform.zoom_level > 1.0 then
                    local zoom_text = string.format("H: %dx", math.floor(waveform.zoom_level))
                    local zoom_w, zoom_h = r.ImGui_CalcTextSize(ctx, zoom_text)
                    local zoom_x = footer_x + footer_width - zoom_w - 5
                    
                    r.ImGui_DrawList_AddText(draw_list, zoom_x, y_offset, text_color, zoom_text)
                    y_offset = y_offset + zoom_h + 2  
                end
                
                if waveform.vertical_zoom ~= 1.0 then
                    local vzoom_text = string.format("V: %.1fx", waveform.vertical_zoom)
                    local vzoom_w, vzoom_h = r.ImGui_CalcTextSize(ctx, vzoom_text)
                    local vzoom_x = footer_x + footer_width - vzoom_w - 5
                    
                    r.ImGui_DrawList_AddText(draw_list, vzoom_x, y_offset, text_color, vzoom_text)
                end
            end
            
            if r.ImGui_IsItemHovered(ctx) and (playback.selected_file ~= "" or playback.current_playing_file ~= "") then
                local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx)
                local normalized_x = (mouse_x - footer_x) / footer_width
                normalized_x = math.max(0, math.min(1, normalized_x))
                local file_path = playback.current_playing_file ~= "" and playback.current_playing_file or (ui.selected_index > 0 and ui.visible_files[ui.selected_index] and ui.visible_files[ui.selected_index].path)
                
                local wheel_delta = r.ImGui_GetMouseWheel(ctx)
                if wheel_delta ~= 0 and is_audio_file then
                    local ctrl_down = r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Ctrl())
                    local alt_down = r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Alt())
                    
                    if ctrl_down and alt_down then
                        local zoom_factor = 1.1
                        if wheel_delta > 0 then
                            waveform.vertical_zoom = waveform.vertical_zoom * zoom_factor
                        else
                            waveform.vertical_zoom = waveform.vertical_zoom / zoom_factor
                        end
                        waveform.vertical_zoom = math.max(0.5, math.min(10.0, waveform.vertical_zoom))
                    elseif ctrl_down then
                        local old_zoom = waveform.zoom_level
                        local old_visible_samples = 1.0 / old_zoom
                        local old_max_scroll = math.max(0, 1.0 - old_visible_samples)
                        local old_scroll_pos = waveform.scroll_offset * old_max_scroll
                        local old_mouse_abs_pos = old_scroll_pos + (normalized_x * old_visible_samples)
                        
                        local zoom_factor = 1.1
                        if wheel_delta > 0 then
                            waveform.zoom_level = waveform.zoom_level * zoom_factor
                        else
                            waveform.zoom_level = waveform.zoom_level / zoom_factor
                        end
                        waveform.zoom_level = math.max(1.0, math.min(8.0, waveform.zoom_level))
                        
                        if waveform.zoom_level <= 1.0 then
                            waveform.scroll_offset = 0.0
                        else
                            local new_visible_samples = 1.0 / waveform.zoom_level
                            local new_max_scroll = math.max(0, 1.0 - new_visible_samples)
                            local new_scroll_pos = old_mouse_abs_pos - (normalized_x * new_visible_samples)
                            new_scroll_pos = math.max(0, math.min(new_max_scroll, new_scroll_pos))
                            waveform.scroll_offset = new_max_scroll > 0 and (new_scroll_pos / new_max_scroll) or 0
                        end
                    else
                        if waveform.zoom_level > 1.0 then
                            local scroll_speed = 0.05
                            waveform.scroll_offset = waveform.scroll_offset - (wheel_delta * scroll_speed)
                            waveform.scroll_offset = math.max(0.0, math.min(1.0, waveform.scroll_offset))
                        end
                    end
                end
                
                if r.ImGui_IsMouseClicked(ctx, 0) and not grid_hovered and not solo_hovered and not spectral_hovered then
                    waveform.play_cursor_position = normalized_x
                    
                    waveform.selection_active = false
                    waveform.monitor_sel_start = 0
                    waveform.monitor_sel_end = 0
                    waveform.normalized_sel_start = 0
                    waveform.normalized_sel_end = 0
                    waveform.monitor_file_path = ""
                    waveform.is_dragging = true
                    waveform.selection_start = normalized_x
                    waveform.selection_end = normalized_x
                    waveform.selection_active = true
                    
                    if file_path and file_path ~= "" then
                        local source = r.PCM_Source_CreateFromFile(file_path)
                        if source then
                            local file_length = r.GetMediaSourceLength(source)
                            r.PCM_Source_Destroy(source)
                            if playback.playing_source and playback.state == "playing" then
                                local click_time = normalized_x * file_length
                                r.PCM_Source_SetPosition(playback.playing_source, click_time)
                                playback.paused_position = click_time
                            end
                        end
                    end
                end
                
                if r.ImGui_IsMouseClicked(ctx, 1) and not grid_hovered then
                    waveform.play_cursor_position = 0
                    if file_path and file_path ~= "" and playback.playing_source and playback.state == "playing" then
                        r.PCM_Source_SetPosition(playback.playing_source, 0)
                        playback.paused_position = 0
                    end
                end
                
                if waveform.is_dragging then
                    waveform.selection_end = normalized_x
                end
            end
            if waveform.is_dragging and not r.ImGui_IsMouseDown(ctx, 0) then
                waveform.is_dragging = false
                local file_path = playback.current_playing_file ~= "" and playback.current_playing_file or (ui.selected_index > 0 and ui.visible_files[ui.selected_index] and ui.visible_files[ui.selected_index].path)
                if waveform.selection_active and file_path and file_path ~= "" then
                    local source = r.PCM_Source_CreateFromFile(file_path)
                    local file_length = 0
                    if source then
                        file_length = r.GetMediaSourceLength(source) or 0
                        r.PCM_Source_Destroy(source)
                    end
                    if file_length <= 0 then
                        waveform.selection_active = false
                    elseif file_length > 0 then
                        local start_norm = math.min(waveform.selection_start, waveform.selection_end)
                        local end_norm = math.max(waveform.selection_start, waveform.selection_end)
                        if math.abs(end_norm - start_norm) < 0.01 then
                            if use_cf_view and playback.playing_preview then
                                local pos = start_norm * file_length
                                if pos and pos >= 0 then
                                    r.CF_Preview_SetValue(playback.playing_preview, "D_POSITION", pos)
                                    if not r.CF_Preview_GetValue(playback.playing_preview, "B_PLAYING") then
                                        r.CF_Preview_Play(playback.playing_preview)
                                    end
                                end
                            end
                            waveform.selection_active = false
                        else
                            local sel_start = start_norm * file_length
                            local sel_end = end_norm * file_length
                            if not sel_start or not sel_end or sel_start < 0 or sel_end < 0 then
                                waveform.selection_active = false
                            else
                                waveform.normalized_sel_start = start_norm
                                waveform.normalized_sel_end = end_norm
                                waveform.monitor_sel_start = start_norm * file_length
                                waveform.monitor_sel_end = end_norm * file_length
                                waveform.monitor_file_path = file_path
                                if playback.effective_playrate and playback.effective_playrate > 0 then
                                    update_monitor_positions()
                                end
                                if playback.auto_play then
                                    start_playback(file_path)
                                end
                            end
                        end
                    end
                end
            end
        end
        
        r.ImGui_EndChild(ctx)
        
        if cache_mgmt.scan_message ~= "" then
            local viewport_center_x, viewport_center_y = r.ImGui_Viewport_GetCenter(r.ImGui_GetWindowViewport(ctx))
            r.ImGui_SetNextWindowPos(ctx, viewport_center_x, viewport_center_y, r.ImGui_Cond_Always(), 0.5, 0.5)
            
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 8)
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 20, 15)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), 0x000000E6)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), 0x404040FF)
            
            local flags = r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_NoResize() | 
                         r.ImGui_WindowFlags_NoMove() | r.ImGui_WindowFlags_NoScrollbar() |
                         r.ImGui_WindowFlags_NoScrollWithMouse() | r.ImGui_WindowFlags_AlwaysAutoResize()
            
            if r.ImGui_Begin(ctx, "##CacheNotification", true, flags) then
                local message_color = cache_mgmt.scan_message:match("up%-to%-date") and 0x00FF00FF or 
                                     (cache_mgmt.scan_message:match("new") or cache_mgmt.scan_message:match("modified") or cache_mgmt.scan_message:match("removed")) and 0x00AAFFFF or 
                                     0xFFFFFFFF
                
                r.ImGui_PushFont(ctx, normal_font, 11)
                r.ImGui_TextColored(ctx, message_color, cache_mgmt.scan_message)
                r.ImGui_PopFont(ctx)
                
                r.ImGui_End(ctx)
            end
            
            r.ImGui_PopStyleColor(ctx, 2)
            r.ImGui_PopStyleVar(ctx, 2)
            
            if cache_mgmt.message_timer and os.time() - cache_mgmt.message_timer > 3 then
                cache_mgmt.scan_message = ""
                cache_mgmt.message_timer = nil
            end
        end
        
        r.ImGui_End(ctx)
    end
    
    draw_progress_window()
    monitor_transport_state()
    
    r.ImGui_PopStyleColor(ctx, 4)
    r.ImGui_PopStyleVar(ctx, 1)
    
    if playback.playing_preview and not playback.is_paused and waveform.monitor_sel_start and waveform.monitor_sel_end and math.abs(waveform.monitor_sel_end - waveform.monitor_sel_start) > 0.01 and not playback.loop_play then
        local ok, pos = r.CF_Preview_GetValue(playback.playing_preview, "D_POSITION")
        if ok and pos >= waveform.monitor_sel_end then
            stop_playback(false)
        end
    elseif playback.playing_preview and not playback.is_paused and waveform.monitor_sel_start and waveform.monitor_sel_end and math.abs(waveform.monitor_sel_end - waveform.monitor_sel_start) > 0.01 and playback.loop_play then
        local ok, pos = r.CF_Preview_GetValue(playback.playing_preview, "D_POSITION")
        if ok and pos >= waveform.monitor_sel_end then
            r.CF_Preview_SetValue(playback.playing_preview, "D_POSITION", waveform.monitor_sel_start)
            playback.prev_play_cursor = waveform.monitor_sel_start
        end
    end
    draw_category_manager()
    draw_rename_folder_popup()
    r.ImGui_PopFont(ctx)
    handle_reaper_drop()
    r.ImGui_SetNextFrameWantCaptureKeyboard(ctx, true)
    if open then
        r.defer(loop)
    else
        on_exit()
    end
end
local function exit_script()
    save_options()
    save_browser_position()
    on_exit()
end
r.atexit(exit_script)
load_locations()
load_collections()

if ui.current_view_mode ~= "collections" and file_location.remember_last_location and file_location.selected_location_index > 0 then
    if file_location.selected_location_index >= 1 and file_location.selected_location_index <= #file_location.locations then
        file_location.current_location = file_location.locations[file_location.selected_location_index]
    else
        file_location.selected_location_index = 1
        file_location.current_location = file_location.locations[1] or ""
    end
    if file_location.current_location and file_location.current_location ~= "" then
        local success, files = pcall(read_directory_recursive, file_location.current_location)
        if success and files then
            file_location.current_files = files
        else
            file_location.selected_location_index = 1
            file_location.current_location = file_location.locations[1] or ""
            if file_location.current_location ~= "" then
                file_location.current_files = read_directory_recursive(file_location.current_location, false)
            end
        end
    end
end
check_numa_player_installed()
load_browser_position()
r.defer(loop)




































