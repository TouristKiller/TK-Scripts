-- @description TK Indestructible Track
-- @author TouristKiller
-- @version 1.3
-- @changelog:
--   + Fixed: Auto-save no longer triggers on LFO/animation changes in plugins
--   + Fixed: Base64 plugin state data excluded from change detection
--   + Improved: Smarter chunk comparison that ignores volatile plugin data
--   + Changed: Default check interval increased to 1.0 sec (range 0.5-5.0 sec)
-------------------------------------------------------------------
local r = reaper

local SCRIPT_NAME = "TK Indestructible Track"
local SCRIPT_VERSION = "1.3"

if not r.ImGui_CreateContext then
    r.ShowMessageBox("ReaImGui is required for this script.\nInstall via ReaPack.", SCRIPT_NAME, 0)
    return
end

if not r.BR_GetMediaItemGUID then
    r.ShowMessageBox("SWS Extension is required for this script.", SCRIPT_NAME, 0)
    return
end

local DATA_DIR = r.GetResourcePath() .. "/Data/TK_IndestructibleTrack/"
local CONFIG_FILE = DATA_DIR .. "TK_IndestructibleTrack_config.json"
local TRACK_FILE = DATA_DIR .. "TK_IndestructibleTrack_data.json"
local HISTORY_DIR = DATA_DIR .. "history/"
local MEDIA_DIR = DATA_DIR .. "media/"

local ctx = r.ImGui_CreateContext(SCRIPT_NAME)
local font_loaded = false
local main_font
local title_font
local shield_image = nil
local shield_loaded = false

local SCRIPT_PATH = debug.getinfo(1, "S").source:match("@?(.*)[/\\]") or "."

local default_config = {
    track_name = "Indestructible",
    check_interval = 1.0,
    max_undo_history = 50,
    auto_backup_count = 5,
    show_notifications = true,
    track_color = 0x1E5A8A,
    auto_load_on_start = true
}

local config = {}
local state = {
    track_guid = nil,
    track_ptr = nil,
    last_chunk = nil,
    last_normalized_chunk = nil,
    last_check_time = 0,
    last_project_state = 0,
    undo_history = {},
    undo_index = 0,
    is_monitoring = false,
    show_settings = false,
    status_message = "",
    status_time = 0
}

local COLORS = {
    bg = 0x141414FF,
    bg_child = 0x1A1A1AFF,
    header = 0x1A1A1AFF,
    header_active = 0x1A1A1AFF,
    frame = 0x2A2A2AFF,
    frame_hover = 0x3A3A3AFF,
    button = 0x3A3A3AFF,
    button_hover = 0x4A4A4AFF,
    button_active = 0x5A5A5AFF,
    text = 0xE0E0E0FF,
    text_dim = 0x707070FF,
    border = 0x141414FF,
    success = 0x6ABF6AFF,
    warning = 0xD4A844FF,
    error = 0xCC6666FF,
    accent = 0x5A9FD4FF,
    shield_white = 0xFFFFFFFF,
    shield_light = 0x7AB8E0FF,
    shield_dark = 0x1E5A8AFF
}

local WINDOW_WIDTH = 280
local WINDOW_HEIGHT = 290

local function EnsureDirectories()
    r.RecursiveCreateDirectory(DATA_DIR, 0)
    r.RecursiveCreateDirectory(HISTORY_DIR, 0)
    r.RecursiveCreateDirectory(MEDIA_DIR, 0)
end

local function CopyFile(src, dst)
    local src_file = io.open(src, "rb")
    if not src_file then return false end
    local content = src_file:read("*all")
    src_file:close()
    
    local dst_file = io.open(dst, "wb")
    if not dst_file then return false end
    dst_file:write(content)
    dst_file:close()
    return true
end

local function GetFileName(path)
    return path:match("([^/\\]+)$") or path
end

local function FileExists(path)
    local f = io.open(path, "r")
    if f then f:close() return true end
    return false
end

local function JsonEncode(tbl)
    local json = "{"
    local first = true
    for k, v in pairs(tbl) do
        if not first then json = json .. "," end
        first = false
        json = json .. '"' .. tostring(k) .. '":'
        if type(v) == "string" then
            v = v:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r')
            json = json .. '"' .. v .. '"'
        elseif type(v) == "number" then
            json = json .. tostring(v)
        elseif type(v) == "boolean" then
            json = json .. (v and "true" or "false")
        elseif type(v) == "table" then
            json = json .. JsonEncode(v)
        else
            json = json .. "null"
        end
    end
    return json .. "}"
end

local function JsonDecode(str)
    if not str or str == "" then return nil end
    local success, result = pcall(function()
        str = str:gsub('%s*\n%s*', '')
        local tbl = {}
        str = str:match('^%s*{(.*)}%s*$')
        if not str then return nil end
        for key, val in str:gmatch('"([^"]+)"%s*:%s*("?[^,}]+"?)') do
            val = val:gsub('^"', ''):gsub('"$', '')
            if val == "true" then val = true
            elseif val == "false" then val = false
            elseif tonumber(val) then val = tonumber(val)
            else
                val = val:gsub('\\n', '\n'):gsub('\\r', '\r'):gsub('\\"', '"'):gsub('\\\\', '\\')
            end
            tbl[key] = val
        end
        return tbl
    end)
    return success and result or nil
end

local function SaveConfig()
    EnsureDirectories()
    local f = io.open(CONFIG_FILE, "w")
    if f then
        f:write(JsonEncode(config))
        f:close()
    end
end

local function LoadConfig()
    local f = io.open(CONFIG_FILE, "r")
    if f then
        local content = f:read("*all")
        f:close()
        local loaded = JsonDecode(content)
        if loaded then
            for k, v in pairs(default_config) do
                config[k] = loaded[k] ~= nil and loaded[k] or v
            end
            return
        end
    end
    for k, v in pairs(default_config) do
        config[k] = v
    end
end

local function SetStatus(msg, is_error)
    state.status_message = msg
    state.status_time = r.time_precise()
    if config.show_notifications then
        if is_error then
            r.ShowConsoleMsg("[" .. SCRIPT_NAME .. "] ERROR: " .. msg .. "\n")
        end
    end
end

local function NormalizeChunkForComparison(chunk)
    if not chunk then return nil end
    local lines = {}
    local in_vst_block = false
    local skip_binary = false
    
    for line in chunk:gmatch("[^\n]+") do
        if line:match("^%s*<VST") or line:match("^%s*<AU") or line:match("^%s*<CLAP") or line:match("^%s*<JS") or line:match("^%s*<DX") then
            in_vst_block = true
            skip_binary = false
            table.insert(lines, line)
        elseif in_vst_block and line:match("^%s*>") then
            in_vst_block = false
            skip_binary = false
            table.insert(lines, line)
        elseif in_vst_block then
            if line:match("^%s*[A-Za-z0-9+/=]+%s*$") and #line > 20 then
                skip_binary = true
            elseif skip_binary and line:match("^%s*[A-Za-z0-9+/=:?]+%s*$") then
            else
                skip_binary = false
                if not line:match("^%s*SEL%s") and
                   not line:match("^%s*FXCHAIN_SHOW%s") and
                   not line:match("^%s*FLOATPOS%s") and
                   not line:match("^%s*WNDPOS%s") and
                   not line:match("^%s*SHOW%s") and
                   not line:match("^%s*LASTSEL%s") and
                   not line:match("^%s*CURPOS%s") and
                   not line:match("^%s*SCROLL%s") and
                   not line:match("^%s*ZOOM%s") and
                   not line:match("^%s*VZOOM%s") and
                   not line:match("^%s*CFGEDIT%s") then
                    table.insert(lines, line)
                end
            end
        else
            if not line:match("^%s*SEL%s") and
               not line:match("^%s*FXCHAIN_SHOW%s") and
               not line:match("^%s*FLOATPOS%s") and
               not line:match("^%s*WNDPOS%s") and
               not line:match("^%s*SHOW%s") and
               not line:match("^%s*LASTSEL%s") and
               not line:match("^%s*CURPOS%s") and
               not line:match("^%s*SCROLL%s") and
               not line:match("^%s*ZOOM%s") and
               not line:match("^%s*VZOOM%s") and
               not line:match("^%s*CFGEDIT%s") then
                table.insert(lines, line)
            end
        end
    end
    
    return table.concat(lines, "\n")
end

local function GetTrackChunk(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return nil end
    local retval, chunk = r.GetTrackStateChunk(track, "", false)
    return retval and chunk or nil
end

local function SetTrackChunk(track, chunk)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end
    local result = r.SetTrackStateChunk(track, chunk, false)
    r.Main_OnCommand(40047, 0)
    r.UpdateArrange()
    r.TrackList_AdjustWindows(false)
    return result
end

local function GetMediaItemsData(track)
    if not track then return {} end
    local items = {}
    local item_count = r.CountTrackMediaItems(track)
    for i = 0, item_count - 1 do
        local item = r.GetTrackMediaItem(track, i)
        if item then
            local item_data = {
                guid = r.BR_GetMediaItemGUID(item),
                position = r.GetMediaItemInfo_Value(item, "D_POSITION"),
                length = r.GetMediaItemInfo_Value(item, "D_LENGTH"),
                sources = {}
            }
            local take_count = r.CountTakes(item)
            for t = 0, take_count - 1 do
                local take = r.GetTake(item, t)
                if take then
                    local source = r.GetMediaItemTake_Source(take)
                    if source then
                        local source_path = r.GetMediaSourceFileName(source)
                        table.insert(item_data.sources, {
                            name = r.GetTakeName(take),
                            path = source_path
                        })
                    end
                end
            end
            table.insert(items, item_data)
        end
    end
    return items
end

local function CopyMediaAndUpdateChunk(chunk)
    EnsureDirectories()
    local updated_chunk = chunk
    local copied_count = 0
    
    for file_path in chunk:gmatch('FILE%s+"([^"]+)"') do
        if file_path ~= "" and not file_path:match("^%s*$") then
            local filename = GetFileName(file_path)
            local dest_path = MEDIA_DIR .. filename
            
            if not dest_path:lower():match(MEDIA_DIR:lower():gsub("[%-%.%+%[%]%(%)%$%^%%%?%*]", "%%%1")) then
                if FileExists(file_path) and not FileExists(dest_path) then
                    if CopyFile(file_path, dest_path) then
                        copied_count = copied_count + 1
                    end
                end
                
                if FileExists(dest_path) then
                    local escaped_path = file_path:gsub("([%-%.%+%[%]%(%)%$%^%%%?%*])", "%%%1")
                    local escaped_dest = dest_path:gsub("\\", "/")
                    updated_chunk = updated_chunk:gsub('FILE%s+"' .. escaped_path .. '"', 'FILE "' .. escaped_dest .. '"')
                end
            end
        end
    end
    
    if copied_count > 0 then
        SetStatus(copied_count .. " media file(s) copied")
    end
    
    return updated_chunk
end

local function SaveTrackData()
    local track = state.track_ptr
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end
    
    local chunk = GetTrackChunk(track)
    if not chunk then return false end
    
    chunk = CopyMediaAndUpdateChunk(chunk)
    
    EnsureDirectories()
    
    local f = io.open(TRACK_FILE, "r")
    if f then
        local old_content = f:read("*all")
        f:close()
        if old_content and old_content ~= "" then
            local backup_name = HISTORY_DIR .. "backup_" .. os.date("%Y%m%d_%H%M%S") .. ".json"
            local bf = io.open(backup_name, "w")
            if bf then
                bf:write(old_content)
                bf:close()
            end
            CleanupOldBackups()
        end
    end
    
    chunk = chunk:gsub("\n", "<<<NEWLINE>>>")
    
    local data = {
        version = SCRIPT_VERSION,
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        track_name = config.track_name,
        chunk = chunk,
        media_items = GetMediaItemsData(track)
    }
    
    local f = io.open(TRACK_FILE, "w")
    if f then
        f:write(JsonEncode(data))
        f:close()
        return true
    end
    return false
end

function CleanupOldBackups()
    local files = {}
    local idx = 0
    
    while true do
        local filename = r.EnumerateFiles(HISTORY_DIR, idx)
        if not filename then break end
        if filename:match("^backup_.*%.json$") then
            table.insert(files, filename)
        end
        idx = idx + 1
    end
    
    table.sort(files, function(a, b) return a > b end)
    
    while #files > config.auto_backup_count do
        local to_delete = table.remove(files)
        os.remove(HISTORY_DIR .. to_delete)
    end
end

local function LoadTrackData()
    local f = io.open(TRACK_FILE, "r")
    if not f then return nil end
    local content = f:read("*all")
    f:close()
    
    if not content or content == "" then return nil end
    
    local data = {}
    
    local chunk_marker = '"chunk":"'
    local chunk_start = content:find(chunk_marker, 1, true)
    if chunk_start then
        chunk_start = chunk_start + #chunk_marker
        
        local search_pos = chunk_start
        local chunk_end = nil
        
        while true do
            local quote_pos = content:find('"', search_pos, true)
            if not quote_pos then break end
            
            local backslash_count = 0
            local check_pos = quote_pos - 1
            while check_pos >= 1 and content:sub(check_pos, check_pos) == '\\' do
                backslash_count = backslash_count + 1
                check_pos = check_pos - 1
            end
            
            if backslash_count % 2 == 0 then
                chunk_end = quote_pos
                break
            end
            
            search_pos = quote_pos + 1
        end
        
        if chunk_end then
            local chunk_raw = content:sub(chunk_start, chunk_end - 1)
            chunk_raw = chunk_raw:gsub("<<<NEWLINE>>>", "\n")
            chunk_raw = chunk_raw:gsub('\\n', '\n')
            chunk_raw = chunk_raw:gsub('\\"', '"')
            chunk_raw = chunk_raw:gsub('\\\\', '\\')
            data.chunk = chunk_raw
        end
    end
    
    local name_match = content:match('"track_name":"([^"]*)"')
    if name_match then
        data.track_name = name_match
    end
    
    return data
end

local function AddToUndoHistory(chunk)
    if state.undo_index < #state.undo_history then
        for i = #state.undo_history, state.undo_index + 1, -1 do
            table.remove(state.undo_history, i)
        end
    end
    
    table.insert(state.undo_history, {
        chunk = chunk,
        timestamp = os.date("%H:%M:%S")
    })
    
    while #state.undo_history > config.max_undo_history do
        table.remove(state.undo_history, 1)
    end
    
    state.undo_index = #state.undo_history
end

local function UndoTrack()
    if state.undo_index <= 1 then
        SetStatus("No earlier states available")
        return false
    end
    
    state.undo_index = state.undo_index - 1
    local history_entry = state.undo_history[state.undo_index]
    
    if state.track_ptr and r.ValidatePtr(state.track_ptr, "MediaTrack*") then
        r.Undo_BeginBlock()
        r.PreventUIRefresh(1)
        SetTrackChunk(state.track_ptr, history_entry.chunk)
        state.last_chunk = history_entry.chunk
        state.last_normalized_chunk = NormalizeChunkForComparison(history_entry.chunk)
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("Indestructible Track - Undo", -1)
        SetStatus("Undo to state " .. state.undo_index .. "/" .. #state.undo_history)
        return true
    end
    return false
end

local function RedoTrack()
    if state.undo_index >= #state.undo_history then
        SetStatus("No later states available")
        return false
    end
    
    state.undo_index = state.undo_index + 1
    local history_entry = state.undo_history[state.undo_index]
    
    if state.track_ptr and r.ValidatePtr(state.track_ptr, "MediaTrack*") then
        r.Undo_BeginBlock()
        r.PreventUIRefresh(1)
        SetTrackChunk(state.track_ptr, history_entry.chunk)
        state.last_chunk = history_entry.chunk
        state.last_normalized_chunk = NormalizeChunkForComparison(history_entry.chunk)
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("Indestructible Track - Redo", -1)
        SetStatus("Redo to state " .. state.undo_index .. "/" .. #state.undo_history)
        return true
    end
    return false
end

local function FindIndestructibleTrack()
    local track_count = r.CountTracks(0)
    for i = 0, track_count - 1 do
        local track = r.GetTrack(0, i)
        local retval, name = r.GetTrackName(track)
        if name == config.track_name then
            return track, r.BR_GetMediaItemGUID and r.GetTrackGUID(track) or nil
        end
    end
    return nil, nil
end

local function CreateIndestructibleTrack()
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    
    r.InsertTrackAtIndex(0, true)
    local track = r.GetTrack(0, 0)
    
    if track then
        r.GetSetMediaTrackInfo_String(track, "P_NAME", config.track_name, true)
        
        local color = r.ColorToNative(
            (config.track_color >> 16) & 0xFF,
            (config.track_color >> 8) & 0xFF,
            config.track_color & 0xFF
        ) | 0x1000000
        r.SetTrackColor(track, color)
        
        state.track_ptr = track
        state.track_guid = r.GetTrackGUID(track)
        state.last_chunk = GetTrackChunk(track)
        state.last_normalized_chunk = NormalizeChunkForComparison(state.last_chunk)
        
        if state.last_chunk then
            AddToUndoHistory(state.last_chunk)
        end
    end
    
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("Create Indestructible Track", -1)
    r.TrackList_AdjustWindows(false)
    
    return track
end

local function LoadOrCreateTrack()
    local existing_track = FindIndestructibleTrack()
    
    if existing_track then
        state.track_ptr = existing_track
        state.track_guid = r.GetTrackGUID(existing_track)
        state.last_chunk = GetTrackChunk(existing_track)
        state.last_normalized_chunk = NormalizeChunkForComparison(state.last_chunk)
        if state.last_chunk then
            AddToUndoHistory(state.last_chunk)
        end
        SetStatus("Existing track found and monitored")
        return existing_track
    end
    
    local saved_data = LoadTrackData()
    if saved_data and saved_data.chunk and config.auto_load_on_start then
        r.Undo_BeginBlock()
        r.PreventUIRefresh(1)
        
        r.InsertTrackAtIndex(0, true)
        local track = r.GetTrack(0, 0)
        
        if track then
            local success = SetTrackChunk(track, saved_data.chunk)
            if success then
                r.GetSetMediaTrackInfo_String(track, "P_NAME", config.track_name, true)
                state.track_ptr = track
                state.track_guid = r.GetTrackGUID(track)
                state.last_chunk = saved_data.chunk
                state.last_normalized_chunk = NormalizeChunkForComparison(saved_data.chunk)
                state.is_monitoring = true
                AddToUndoHistory(state.last_chunk)
                SetStatus("Track restored from saved data")
            end
        end
        
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("Restore Indestructible Track", -1)
        r.TrackList_AdjustWindows(false)
        return track
    end
    
    local track = CreateIndestructibleTrack()
    if track then
        state.is_monitoring = true
        SaveTrackData()
        SetStatus("New Indestructible Track created")
    end
    return track
end

local function GetProjectMediaPath()
    local proj_path = r.GetProjectPath()
    if proj_path and proj_path ~= "" then
        return proj_path .. "/"
    end
    local rec_path = r.GetProjectPathEx(0, "")
    if rec_path and rec_path ~= "" then
        return rec_path .. "/"
    end
    return nil
end

local function CopyTrackToProject()
    if not state.track_ptr or not r.ValidatePtr(state.track_ptr, "MediaTrack*") then
        SetStatus("No track to copy", true)
        return false
    end
    
    local proj_path = GetProjectMediaPath()
    if not proj_path then
        r.ShowMessageBox("Please save the project first.\n\nThe track copy needs a project folder to store the media files.", SCRIPT_NAME, 0)
        return false
    end
    
    local chunk = GetTrackChunk(state.track_ptr)
    if not chunk then
        SetStatus("Could not get track data", true)
        return false
    end
    
    local media_dest = proj_path .. "IndestructibleCopy/"
    r.RecursiveCreateDirectory(media_dest, 0)
    
    local updated_chunk = chunk
    local copied_count = 0
    
    for file_path in chunk:gmatch('FILE%s+"([^"]+)"') do
        if file_path ~= "" and not file_path:match("^%s*$") then
            local filename = GetFileName(file_path)
            local dest_path = media_dest .. filename
            
            if FileExists(file_path) then
                if CopyFile(file_path, dest_path) then
                    copied_count = copied_count + 1
                    local escaped_path = file_path:gsub("([%-%.%+%[%]%(%)%$%^%%%?%*])", "%%%1")
                    local escaped_dest = dest_path:gsub("\\", "/")
                    updated_chunk = updated_chunk:gsub('FILE%s+"' .. escaped_path .. '"', 'FILE "' .. escaped_dest .. '"')
                end
            end
        end
    end
    
    updated_chunk = updated_chunk:gsub('NAME%s+"' .. config.track_name .. '"', 'NAME "' .. config.track_name .. ' (Copy)"')
    
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    
    local track_count = r.CountTracks(0)
    r.InsertTrackAtIndex(track_count, true)
    local new_track = r.GetTrack(0, track_count)
    
    if new_track then
        local success = SetTrackChunk(new_track, updated_chunk)
        if success then
            r.GetSetMediaTrackInfo_String(new_track, "P_NAME", config.track_name .. " (Copy)", true)
            SetStatus("Track copied with " .. copied_count .. " media file(s)")
        else
            SetStatus("Failed to create copy", true)
        end
    end
    
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("Copy Indestructible Track to Project", -1)
    r.TrackList_AdjustWindows(false)
    
    return true
end

local last_save_time = 0

local function CheckForChanges()
    if not state.track_ptr or not r.ValidatePtr(state.track_ptr, "MediaTrack*") then
        state.track_ptr = FindIndestructibleTrack()
        if not state.track_ptr then
            state.is_monitoring = false
            return
        end
    end
    
    local current_chunk = GetTrackChunk(state.track_ptr)
    if not current_chunk then return end
    
    local normalized_current = NormalizeChunkForComparison(current_chunk)
    
    if not state.last_normalized_chunk then
        state.last_normalized_chunk = normalized_current
        state.last_chunk = current_chunk
        return
    end
    
    if normalized_current ~= state.last_normalized_chunk then
        local now = r.time_precise()
        if now - last_save_time < 1.0 then return end
        last_save_time = now
        
        AddToUndoHistory(current_chunk)
        state.last_chunk = current_chunk
        state.last_normalized_chunk = normalized_current
        
        if SaveTrackData() then
            SetStatus("Auto-save: change saved (" .. os.date("%H:%M:%S") .. ")")
        else
            SetStatus("ERROR: Could not save change!", true)
        end
    end
end

local function ApplyTheme()
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), COLORS.bg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), COLORS.bg_child)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBg(), COLORS.header)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgActive(), COLORS.header_active)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), COLORS.frame)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), COLORS.frame_hover)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COLORS.button)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), COLORS.button_hover)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), COLORS.button_active)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), COLORS.border)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), COLORS.accent)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), COLORS.accent)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.text)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 8)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 6)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 10, 10)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 6, 4)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 6, 4)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowBorderSize(), 0)
end

local function PopTheme()
    r.ImGui_PopStyleVar(ctx, 6)
    r.ImGui_PopStyleColor(ctx, 13)
end

local function LoadShieldImage()
    if shield_loaded then return end
    shield_loaded = true
    local img_path = SCRIPT_PATH .. "/ISHIELD.png"
    shield_image = r.ImGui_CreateImage(img_path)
    if shield_image then
        r.ImGui_Attach(ctx, shield_image)
    end
end

local function DrawStatusBar()
    local elapsed = r.time_precise() - state.status_time
    if elapsed < 5 and state.status_message ~= "" then
        local alpha = elapsed < 4 and 1.0 or (5 - elapsed)
        local color = COLORS.success
        if state.status_message:match("ERROR") or state.status_message:match("Could not") then
            color = COLORS.error
        elseif state.status_message:match("No ") then
            color = COLORS.warning
        end
        color = (color & 0xFFFFFF00) | math.floor(alpha * 255)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), color)
        r.ImGui_TextWrapped(ctx, state.status_message)
        r.ImGui_PopStyleColor(ctx)
    else
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.text_dim)
        r.ImGui_Text(ctx, "Monitoring active...")
        r.ImGui_PopStyleColor(ctx)
    end
end

local function DrawMainUI()
    LoadShieldImage()
    
    if shield_image then
        r.ImGui_Image(ctx, shield_image, 48, 48)
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + 12)
    end
    r.ImGui_PushFont(ctx, title_font, 18)
    r.ImGui_Text(ctx, "INDESTRUCTIBLE TRACK")
    r.ImGui_PopFont(ctx)
    r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + 8)
    
    r.ImGui_Separator(ctx)
    
    if state.track_ptr and r.ValidatePtr(state.track_ptr, "MediaTrack*") and state.is_monitoring then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.success)
        r.ImGui_Text(ctx, "[*] Track active and monitored")
        r.ImGui_PopStyleColor(ctx)
    else
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.error)
        r.ImGui_Text(ctx, "[ ] Track not found")
        r.ImGui_PopStyleColor(ctx)
        
        if r.ImGui_Button(ctx, "Create/Restore Track", -1, 0) then
            LoadOrCreateTrack()
            state.last_project_state = r.GetProjectStateChangeCount(0)
        end
    end
    
    r.ImGui_Separator(ctx)
    
    r.ImGui_Text(ctx, "Undo History: " .. state.undo_index .. " / " .. #state.undo_history)
    
    local undo_disabled = state.undo_index <= 1
    local redo_disabled = state.undo_index >= #state.undo_history
    
    local button_width = (WINDOW_WIDTH - 24) / 2
    
    if undo_disabled then r.ImGui_BeginDisabled(ctx) end
    if r.ImGui_Button(ctx, "< Undo##track", button_width, 0) then
        UndoTrack()
    end
    if undo_disabled then r.ImGui_EndDisabled(ctx) end
    
    r.ImGui_SameLine(ctx)
    
    if redo_disabled then r.ImGui_BeginDisabled(ctx) end
    if r.ImGui_Button(ctx, "Redo >##track", button_width, 0) then
        RedoTrack()
    end
    if redo_disabled then r.ImGui_EndDisabled(ctx) end
    
    r.ImGui_Separator(ctx)
    
    if r.ImGui_Button(ctx, "Settings", -1, 0) then
        state.show_settings = not state.show_settings
    end
    
    if r.ImGui_Button(ctx, "Save Now", -1, 0) then
        if SaveTrackData() then
            SetStatus("Manually saved!")
        end
    end
    
    local has_track = state.track_ptr and r.ValidatePtr(state.track_ptr, "MediaTrack*")
    if not has_track then r.ImGui_BeginDisabled(ctx) end
    if r.ImGui_Button(ctx, "Copy to Project", -1, 0) then
        CopyTrackToProject()
    end
    if not has_track then r.ImGui_EndDisabled(ctx) end
    
    r.ImGui_Separator(ctx)
    
    DrawStatusBar()
end

local function DrawSettingsUI()
    r.ImGui_Text(ctx, "SETTINGS")
    r.ImGui_Separator(ctx)
    
    local changed, new_val
    
    r.ImGui_Text(ctx, "Track name:")
    changed, new_val = r.ImGui_InputText(ctx, "##trackname", config.track_name)
    if changed then config.track_name = new_val end
    
    r.ImGui_Text(ctx, "Check interval (sec):")
    changed, new_val = r.ImGui_SliderDouble(ctx, "##interval", config.check_interval, 0.5, 5.0, "%.1f")
    if changed then config.check_interval = new_val end
    
    r.ImGui_Text(ctx, "Max undo history:")
    changed, new_val = r.ImGui_SliderInt(ctx, "##maxundo", config.max_undo_history, 10, 200)
    if changed then config.max_undo_history = new_val end
    
    r.ImGui_Text(ctx, "Backups to keep:")
    changed, new_val = r.ImGui_SliderInt(ctx, "##backups", config.auto_backup_count, 1, 20)
    if changed then config.auto_backup_count = new_val end
    
    changed, new_val = r.ImGui_Checkbox(ctx, "Show notifications", config.show_notifications)
    if changed then config.show_notifications = new_val end
    
    changed, new_val = r.ImGui_Checkbox(ctx, "Auto-load on start", config.auto_load_on_start)
    if changed then config.auto_load_on_start = new_val end
    
    r.ImGui_Separator(ctx)
    
    if r.ImGui_Button(ctx, "Save and Close", -1, 0) then
        SaveConfig()
        state.show_settings = false
        SetStatus("Settings saved")
    end
    
    if r.ImGui_Button(ctx, "Cancel", -1, 0) then
        LoadConfig()
        state.show_settings = false
    end
end

local function loop()
    if not font_loaded then
        main_font = r.ImGui_CreateFont("Segoe UI", 13)
        title_font = r.ImGui_CreateFont("Segoe UI", 18)
        r.ImGui_Attach(ctx, main_font)
        r.ImGui_Attach(ctx, title_font)
        font_loaded = true
    end
    
    local now = r.time_precise()
    if state.is_monitoring and now - state.last_check_time >= config.check_interval then
        state.last_check_time = now
        CheckForChanges()
    end
    
    ApplyTheme()
    r.ImGui_PushFont(ctx, main_font, 13)
    
    local window_flags = r.ImGui_WindowFlags_NoCollapse() | r.ImGui_WindowFlags_NoResize() | r.ImGui_WindowFlags_NoTitleBar()
    r.ImGui_SetNextWindowSize(ctx, WINDOW_WIDTH, WINDOW_HEIGHT, r.ImGui_Cond_Always())
    
    local visible, open = r.ImGui_Begin(ctx, SCRIPT_NAME, true, window_flags)
    
    if visible then
        if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape()) then
            open = false
        end
        
        if state.show_settings then
            DrawSettingsUI()
        else
            DrawMainUI()
        end
        r.ImGui_End(ctx)
    end
    
    r.ImGui_PopFont(ctx)
    PopTheme()
    
    if open then
        r.defer(loop)
    else
        if state.track_ptr and r.ValidatePtr(state.track_ptr, "MediaTrack*") then
            SaveTrackData()
        end
        SaveConfig()
    end
end

local function Init()
    EnsureDirectories()
    LoadConfig()
    
    local track = LoadOrCreateTrack()
    if track then
        state.is_monitoring = true
        state.last_project_state = r.GetProjectStateChangeCount(0)
    end
    
    r.defer(loop)
end

Init()
