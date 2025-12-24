-- @description TK Indestructible Track
-- @author TouristKiller
-- @version 2.4
-- @changelog:
--   + added: Compact mode settings split into tabs (General / Display)
--   + added: Icon size slider with proportional scaling
--   + added: X/Y offset sliders with +/- buttons for precise positioning
--   + added: Show preview checkbox for live positioning
--   + added: Lock position option to lock widget position within TCP
--   + added: Icon only mode
--   + added: No background mode
--   + improved: Full TCP width range for X offset
-------------------------------------------------------------------
local r = reaper

local SCRIPT_NAME = "TK Indestructible Track"
local SCRIPT_VERSION = "2.3"

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
local LOCK_FILE = DATA_DIR .. "TK_IndestructibleTrack.lock"
local HISTORY_DIR = DATA_DIR .. "history/"
local SNAPSHOTS_DIR = DATA_DIR .. "snapshots/"
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
    auto_load_on_start = true,
    tempo_check_enabled = true,
    remember_tempo_choice = false,
    tempo_choice = "time",
    track_position = "top",
    track_pinned = false,
    compact_mode = false,
    compact_offset_x = 2,
    compact_offset_y = 0,
    compact_icon_only = false,
    compact_no_bg = false,
    compact_icon_size = 28,
    compact_lock_position = false,
    compact_locked_x = nil,
    compact_locked_y = nil
}

local compact_ctx = nil
local COMPACT_WIDTH = 180
local COMPACT_HEIGHT = 28

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
    show_undo_list = false,
    show_backup_list = false,
    show_snapshot_list = false,
    show_snapshot_save = false,
    snapshot_name_input = "",
    show_close_warning = false,
    close_action = nil,
    status_message = "",
    status_time = 0,
    preview_compact = false
}

local available_backups = {}
local available_snapshots = {}

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
local WINDOW_HEIGHT = 350
local MIN_WINDOW_HEIGHT = 350

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
        for key, val in str:gmatch('"([^"]+)"%s*:%s*([^,}]+)') do
            val = val:gsub('^%s+', ''):gsub('%s+$', '')
            if val:match('^".*"$') then
                val = val:sub(2, -2)
                val = val:gsub('\\n', '\n'):gsub('\\r', '\r'):gsub('\\"', '"'):gsub('\\\\', '\\')
            elseif val == "true" then 
                val = true
            elseif val == "false" then 
                val = false
            elseif tonumber(val) then 
                val = tonumber(val)
            end
            tbl[key] = val
        end
        return tbl
    end)
    return success and result or nil
end

local function CreateLockFile()
    local f = io.open(LOCK_FILE, "w")
    if f then
        local proj_name = r.GetProjectName(0, "")
        if proj_name == "" then proj_name = "Untitled" end
        f:write(JsonEncode({
            pid = tostring(r.GetCurrentThreadId and r.GetCurrentThreadId() or os.time()),
            project = proj_name,
            time = os.date("%Y-%m-%d %H:%M:%S")
        }))
        f:close()
        return true
    end
    return false
end

local function RemoveLockFile()
    os.remove(LOCK_FILE)
end

local function CheckLockFile()
    if not FileExists(LOCK_FILE) then return nil end
    local f = io.open(LOCK_FILE, "r")
    if not f then return nil end
    local content = f:read("*all")
    f:close()
    return JsonDecode(content)
end

local function GetSavedDataTimestamp()
    if not FileExists(TRACK_FILE) then return nil end
    local f = io.open(TRACK_FILE, "r")
    if not f then return nil end
    local content = f:read("*all")
    f:close()
    local timestamp = content:match('"timestamp":"([^"]+)"')
    return timestamp
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
                if loaded[k] ~= nil then
                    config[k] = loaded[k]
                else
                    config[k] = v
                end
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
                   not line:match("^%s*CFGEDIT%s") and
                   not line:match("^%s*TRACKHEIGHT%s") then
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
               not line:match("^%s*CFGEDIT%s") and
               not line:match("^%s*PEAKCOL%s") and
               not line:match("^%s*TRACKHEIGHT%s") then
                table.insert(lines, line)
            end
        end
    end
    
    return table.concat(lines, "\n")
end

local function AdjustChunkToTempo(chunk, old_tempo, new_tempo)
    if not chunk or not old_tempo or not new_tempo then return chunk end
    if old_tempo <= 0 or new_tempo <= 0 then return chunk end
    
    local ratio = old_tempo / new_tempo
    
    local adjusted = chunk:gsub("(POSITION%s+)([%d%.]+)", function(prefix, pos)
        local new_pos = tonumber(pos) * ratio
        return prefix .. string.format("%.10f", new_pos)
    end)
    
    adjusted = adjusted:gsub("(LENGTH%s+)([%d%.]+)", function(prefix, len)
        local new_len = tonumber(len) * ratio
        return prefix .. string.format("%.10f", new_len)
    end)
    
    adjusted = adjusted:gsub("(SOFFS%s+)([%d%.%-]+)", function(prefix, soffs)
        local new_soffs = tonumber(soffs) * ratio
        return prefix .. string.format("%.10f", new_soffs)
    end)
    
    adjusted = adjusted:gsub("(FADEIN%s+%d+%s+)([%d%.]+)", function(prefix, fade)
        local new_fade = tonumber(fade) * ratio
        return prefix .. string.format("%.10f", new_fade)
    end)
    
    adjusted = adjusted:gsub("(FADEOUT%s+%d+%s+)([%d%.]+)", function(prefix, fade)
        local new_fade = tonumber(fade) * ratio
        return prefix .. string.format("%.10f", new_fade)
    end)
    
    return adjusted
end

local function GetProjectPinStatus(proj)
    proj = proj or 0
    local retval, val = r.GetProjExtState(proj, SCRIPT_NAME, "track_pinned")
    return retval > 0 and val == "1"
end

local function SetProjectPinStatus(proj, pinned)
    proj = proj or 0
    r.SetProjExtState(proj, SCRIPT_NAME, "track_pinned", pinned and "1" or "0")
    r.MarkProjectDirty(proj)
end

local function GetTrackChunk(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return nil end
    local retval, chunk = r.GetTrackStateChunk(track, "", false)
    return retval and chunk or nil
end

local function SetTrackChunk(track, chunk, preserve_local)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end
    
    if preserve_local ~= false then
        local current_chunk = GetTrackChunk(track)
        if current_chunk then
            local current_trackheight = current_chunk:match("(TRACKHEIGHT [^\n]+)")
            if current_trackheight then
                chunk = chunk:gsub("TRACKHEIGHT [^\n]+", current_trackheight)
            end
        end
    end
    
    local result = r.SetTrackStateChunk(track, chunk, false)
    
    if preserve_local ~= false then
        local should_pin = GetProjectPinStatus(0)
        r.SetMediaTrackInfo_Value(track, "B_TCPPIN", should_pin and 1 or 0)
    end
    
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
    
    local tempo = r.Master_GetTempo()
    
    local data = {
        version = SCRIPT_VERSION,
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        track_name = config.track_name,
        tempo = tempo,
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
    
    local tempo_match = content:match('"tempo":([%d%.]+)')
    if tempo_match then
        data.tempo = tonumber(tempo_match)
    end
    
    return data
end

local function DetectChangeType(old_chunk, new_chunk)
    if not old_chunk then return "Initial state" end
    if not new_chunk then return "Track modified" end
    
    local function ExtractItems(chunk)
        local items = {}
        if not chunk then return items end
        for item_block in chunk:gmatch("<ITEM.-\n>") do
            local pos = item_block:match("POSITION%s+([%d%.]+)")
            local len = item_block:match("LENGTH%s+([%d%.]+)")
            local name = item_block:match('NAME%s+"([^"]*)"')
            local mute = item_block:match("MUTE%s+(%d+)")
            local vol = item_block:match("VOLPAN%s+([%d%.%-]+)")
            local fadein = item_block:match("FADEIN%s+%d+%s+([%d%.]+)")
            local fadeout = item_block:match("FADEOUT%s+%d+%s+([%d%.]+)")
            table.insert(items, {
                pos = tonumber(pos) or 0,
                len = tonumber(len) or 0,
                name = name or "",
                mute = tonumber(mute) or 0,
                vol = tonumber(vol) or 1,
                fadein = tonumber(fadein) or 0,
                fadeout = tonumber(fadeout) or 0
            })
        end
        return items
    end
    
    local function CountFX(chunk)
        local count = 0
        for _ in chunk:gmatch("<VST") do count = count + 1 end
        for _ in chunk:gmatch("<AU") do count = count + 1 end
        for _ in chunk:gmatch("<CLAP") do count = count + 1 end
        for _ in chunk:gmatch("<JS") do count = count + 1 end
        return count
    end
    
    local function GetVolPan(chunk)
        local vol, pan = chunk:match("VOLPAN%s+([%d%.%-]+)%s+([%d%.%-]+)")
        return tonumber(vol), tonumber(pan)
    end
    
    local function GetMuteSolo(chunk)
        local mute, solo = chunk:match("MUTESOLO%s+(%d+)%s+(%d+)")
        return tonumber(mute), tonumber(solo)
    end
    
    local function GetTrackName(chunk)
        return chunk:match('NAME%s+"([^"]*)"')
    end
    
    local function CountEnvelopes(chunk)
        local count = 0
        for _ in chunk:gmatch("<VOLENV") do count = count + 1 end
        for _ in chunk:gmatch("<PANENV") do count = count + 1 end
        for _ in chunk:gmatch("<PARMENV") do count = count + 1 end
        return count
    end
    
    local old_items = ExtractItems(old_chunk)
    local new_items = ExtractItems(new_chunk)
    
    if #new_items > #old_items then
        return "Item added (" .. #new_items .. " total)"
    elseif #new_items < #old_items then
        return "Item removed (" .. #new_items .. " total)"
    end
    
    if #old_items > 0 and #new_items > 0 and #old_items == #new_items then
        for i = 1, #new_items do
            local o, n = old_items[i], new_items[i]
            if o and n then
                if math.abs(o.pos - n.pos) > 0.001 then
                    return string.format("Item moved (%.2fs)", n.pos)
                end
                if math.abs(o.len - n.len) > 0.001 then
                    return string.format("Item resized (%.2fs)", n.len)
                end
                if o.mute ~= n.mute then
                    return n.mute == 1 and "Item muted" or "Item unmuted"
                end
                if math.abs(o.vol - n.vol) > 0.01 then
                    local db = 20 * math.log(n.vol, 10)
                    return string.format("Item volume: %.1f dB", db)
                end
                if math.abs(o.fadein - n.fadein) > 0.001 then
                    return string.format("Fade in: %.2fs", n.fadein)
                end
                if math.abs(o.fadeout - n.fadeout) > 0.001 then
                    return string.format("Fade out: %.2fs", n.fadeout)
                end
                if o.name ~= n.name and n.name ~= "" then
                    return "Item renamed: " .. n.name
                end
            end
        end
    end
    
    local old_fx = CountFX(old_chunk)
    local new_fx = CountFX(new_chunk)
    if new_fx > old_fx then
        return "FX added (" .. new_fx .. " total)"
    elseif new_fx < old_fx then
        return "FX removed (" .. new_fx .. " total)"
    end
    
    local old_vol, old_pan = GetVolPan(old_chunk)
    local new_vol, new_pan = GetVolPan(new_chunk)
    if old_vol and new_vol and math.abs(old_vol - new_vol) > 0.001 then
        local db = 20 * math.log(new_vol, 10)
        return string.format("Volume: %.1f dB", db)
    end
    if old_pan and new_pan and math.abs(old_pan - new_pan) > 0.001 then
        local pan_str = new_pan == 0 and "C" or (new_pan < 0 and string.format("%.0f%%L", -new_pan * 100) or string.format("%.0f%%R", new_pan * 100))
        return "Pan: " .. pan_str
    end
    
    local old_mute, old_solo = GetMuteSolo(old_chunk)
    local new_mute, new_solo = GetMuteSolo(new_chunk)
    if old_mute ~= new_mute then
        return new_mute == 1 and "Track muted" or "Track unmuted"
    end
    if old_solo ~= new_solo then
        return new_solo == 1 and "Track soloed" or "Track unsoloed"
    end
    
    local old_name = GetTrackName(old_chunk)
    local new_name = GetTrackName(new_chunk)
    if old_name ~= new_name then
        return "Renamed: " .. (new_name or "?")
    end
    
    local old_env = CountEnvelopes(old_chunk)
    local new_env = CountEnvelopes(new_chunk)
    if new_env > old_env then
        return "Envelope added"
    elseif new_env < old_env then
        return "Envelope removed"
    end
    
    return "Track modified"
end

local function AddToUndoHistory(chunk)
    if state.undo_index < #state.undo_history then
        for i = #state.undo_history, state.undo_index + 1, -1 do
            table.remove(state.undo_history, i)
        end
    end
    
    local prev_chunk = state.undo_history[#state.undo_history] and state.undo_history[#state.undo_history].chunk or nil
    local desc = DetectChangeType(prev_chunk, chunk)
    
    table.insert(state.undo_history, {
        chunk = chunk,
        timestamp = os.date("%H:%M:%S"),
        description = desc
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

local function JumpToUndoState(target_index)
    if target_index < 1 or target_index > #state.undo_history then
        return false
    end
    if target_index == state.undo_index then
        return true
    end
    
    state.undo_index = target_index
    local history_entry = state.undo_history[state.undo_index]
    
    if state.track_ptr and r.ValidatePtr(state.track_ptr, "MediaTrack*") then
        r.Undo_BeginBlock()
        r.PreventUIRefresh(1)
        SetTrackChunk(state.track_ptr, history_entry.chunk)
        state.last_chunk = history_entry.chunk
        state.last_normalized_chunk = NormalizeChunkForComparison(history_entry.chunk)
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("Indestructible Track - Jump to state", -1)
        SetStatus("Jumped to state " .. state.undo_index .. "/" .. #state.undo_history)
        return true
    end
    return false
end

local function ScanBackups()
    available_backups = {}
    local idx = 0
    while true do
        local filename = r.EnumerateFiles(HISTORY_DIR, idx)
        if not filename then break end
        if filename:match("^backup_.*%.json$") then
            local timestamp = filename:match("backup_(%d+_%d+)%.json")
            if timestamp then
                local year = timestamp:sub(1, 4)
                local month = timestamp:sub(5, 6)
                local day = timestamp:sub(7, 8)
                local hour = timestamp:sub(10, 11)
                local min = timestamp:sub(12, 13)
                local sec = timestamp:sub(14, 15)
                local display = string.format("%s-%s-%s %s:%s:%s", year, month, day, hour, min, sec)
                table.insert(available_backups, {
                    filename = filename,
                    path = HISTORY_DIR .. filename,
                    display = display,
                    sort_key = timestamp
                })
            end
        end
        idx = idx + 1
    end
    table.sort(available_backups, function(a, b) return a.sort_key > b.sort_key end)
end

local function LoadBackup(backup)
    local f = io.open(backup.path, "r")
    if not f then
        SetStatus("Could not open backup", true)
        return false
    end
    local content = f:read("*all")
    f:close()
    
    local chunk_marker = '"chunk":"'
    local chunk_start = content:find(chunk_marker, 1, true)
    if not chunk_start then
        SetStatus("Invalid backup file", true)
        return false
    end
    
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
    
    if not chunk_end then
        SetStatus("Could not parse backup", true)
        return false
    end
    
    local chunk = content:sub(chunk_start, chunk_end - 1)
    chunk = chunk:gsub("<<<NEWLINE>>>", "\n")
    chunk = chunk:gsub('\\n', '\n')
    chunk = chunk:gsub('\\"', '"')
    chunk = chunk:gsub('\\\\', '\\')
    
    chunk = chunk:gsub('NAME ".-"', 'NAME "' .. config.track_name .. '"', 1)
    
    if not state.track_ptr or not r.ValidatePtr(state.track_ptr, "MediaTrack*") then
        state.track_ptr = FindIndestructibleTrack()
        if not state.track_ptr then
            r.InsertTrackAtIndex(0, true)
            state.track_ptr = r.GetTrack(0, 0)
            r.GetSetMediaTrackInfo_String(state.track_ptr, "P_NAME", config.track_name, true)
            r.GetSetMediaTrackInfo_String(state.track_ptr, "P_EXT:TK_INDESTRUCTIBLE", "1", true)
            state.track_guid = r.GetTrackGUID(state.track_ptr)
        end
    end
    
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    SetTrackChunk(state.track_ptr, chunk)
    r.GetSetMediaTrackInfo_String(state.track_ptr, "P_NAME", config.track_name, true)
    r.GetSetMediaTrackInfo_String(state.track_ptr, "P_EXT:TK_INDESTRUCTIBLE", "1", true)
    state.last_chunk = chunk
    state.last_normalized_chunk = NormalizeChunkForComparison(chunk)
    AddToUndoHistory(chunk)
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("Load Indestructible Track Backup", -1)
    
    SaveTrackData()
    
    SetStatus("Backup loaded: " .. backup.display)
    return true
end

local function ScanSnapshots()
    available_snapshots = {}
    r.RecursiveCreateDirectory(SNAPSHOTS_DIR, 0)
    local idx = 0
    while true do
        local filename = r.EnumerateFiles(SNAPSHOTS_DIR, idx)
        if not filename then break end
        if filename:match("%.json$") then
            local f = io.open(SNAPSHOTS_DIR .. filename, "r")
            if f then
                local content = f:read("*all")
                f:close()
                local name = content:match('"name":"([^"]*)"') or filename:gsub("%.json$", "")
                local timestamp = content:match('"timestamp":"([^"]*)"') or ""
                table.insert(available_snapshots, {
                    filename = filename,
                    path = SNAPSHOTS_DIR .. filename,
                    name = name,
                    timestamp = timestamp,
                    display = name .. " (" .. timestamp .. ")"
                })
            end
        end
        idx = idx + 1
    end
    table.sort(available_snapshots, function(a, b) return a.timestamp > b.timestamp end)
end

local function SaveSnapshot(name)
    if not state.track_ptr or not r.ValidatePtr(state.track_ptr, "MediaTrack*") then
        SetStatus("No track to save", true)
        return false
    end
    
    local chunk = GetTrackChunk(state.track_ptr)
    if not chunk then
        SetStatus("Could not get track data", true)
        return false
    end
    
    r.RecursiveCreateDirectory(SNAPSHOTS_DIR, 0)
    
    local safe_name = name:gsub("[^%w%s%-_]", ""):gsub("%s+", "_")
    if safe_name == "" then safe_name = "snapshot" end
    
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local file_timestamp = os.date("%Y%m%d_%H%M%S")
    local filename = safe_name .. "_" .. file_timestamp .. ".json"
    
    local escaped_chunk = chunk:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "<<<NEWLINE>>>")
    local tempo = r.Master_GetTempo()
    
    local json = string.format(
        '{"name":"%s","timestamp":"%s","tempo":%.6f,"chunk":"%s"}',
        name:gsub('"', '\\"'),
        timestamp,
        tempo,
        escaped_chunk
    )
    
    local f = io.open(SNAPSHOTS_DIR .. filename, "w")
    if not f then
        SetStatus("Could not save snapshot", true)
        return false
    end
    f:write(json)
    f:close()
    
    SetStatus("Snapshot saved: " .. name)
    return true
end

local function LoadSnapshot(snapshot)
    local f = io.open(snapshot.path, "r")
    if not f then
        SetStatus("Could not open snapshot", true)
        return false
    end
    local content = f:read("*all")
    f:close()
    
    local chunk_marker = '"chunk":"'
    local chunk_start = content:find(chunk_marker, 1, true)
    if not chunk_start then
        SetStatus("Invalid snapshot file", true)
        return false
    end
    
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
    
    if not chunk_end then
        SetStatus("Could not parse snapshot", true)
        return false
    end
    
    local chunk = content:sub(chunk_start, chunk_end - 1)
    chunk = chunk:gsub("<<<NEWLINE>>>", "\n")
    chunk = chunk:gsub('\\n', '\n')
    chunk = chunk:gsub('\\"', '"')
    chunk = chunk:gsub('\\\\', '\\')
    
    chunk = chunk:gsub('NAME ".-"', 'NAME "' .. config.track_name .. '"', 1)
    
    if not state.track_ptr or not r.ValidatePtr(state.track_ptr, "MediaTrack*") then
        state.track_ptr = FindIndestructibleTrack()
        if not state.track_ptr then
            r.InsertTrackAtIndex(0, true)
            state.track_ptr = r.GetTrack(0, 0)
            r.GetSetMediaTrackInfo_String(state.track_ptr, "P_NAME", config.track_name, true)
            r.GetSetMediaTrackInfo_String(state.track_ptr, "P_EXT:TK_INDESTRUCTIBLE", "1", true)
            state.track_guid = r.GetTrackGUID(state.track_ptr)
        end
    end
    
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    SetTrackChunk(state.track_ptr, chunk)
    r.GetSetMediaTrackInfo_String(state.track_ptr, "P_NAME", config.track_name, true)
    r.GetSetMediaTrackInfo_String(state.track_ptr, "P_EXT:TK_INDESTRUCTIBLE", "1", true)
    state.last_chunk = chunk
    state.last_normalized_chunk = NormalizeChunkForComparison(chunk)
    AddToUndoHistory(chunk)
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("Load Indestructible Track Snapshot", -1)
    
    SaveTrackData()
    
    SetStatus("Snapshot loaded: " .. snapshot.name)
    return true
end

local function DeleteSnapshot(snapshot)
    os.remove(snapshot.path)
    ScanSnapshots()
    SetStatus("Snapshot deleted: " .. snapshot.name)
end

local function FindIndestructibleTrack()
    local track_count = r.CountTracks(0)
    
    for i = 0, track_count - 1 do
        local track = r.GetTrack(0, i)
        local retval, marker = r.GetSetMediaTrackInfo_String(track, "P_EXT:TK_INDESTRUCTIBLE", "", false)
        if retval and marker == "1" then
            return track, r.BR_GetMediaItemGUID and r.GetTrackGUID(track) or nil
        end
    end
    
    for i = 0, track_count - 1 do
        local track = r.GetTrack(0, i)
        local retval, name = r.GetTrackName(track)
        if name == config.track_name then
            r.GetSetMediaTrackInfo_String(track, "P_EXT:TK_INDESTRUCTIBLE", "1", true)
            return track, r.BR_GetMediaItemGUID and r.GetTrackGUID(track) or nil
        end
    end
    return nil, nil
end

local function CreateIndestructibleTrack()
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    
    local track_count = r.CountTracks(0)
    local insert_index = 0
    if config.track_position == "bottom" then
        insert_index = track_count
    end
    
    r.InsertTrackAtIndex(insert_index, true)
    local track = r.GetTrack(0, insert_index)
    
    if track then
        r.GetSetMediaTrackInfo_String(track, "P_NAME", config.track_name, true)
        r.GetSetMediaTrackInfo_String(track, "P_EXT:TK_INDESTRUCTIBLE", "1", true)
        
        local color = r.ColorToNative(
            (config.track_color >> 16) & 0xFF,
            (config.track_color >> 8) & 0xFF,
            config.track_color & 0xFF
        ) | 0x1000000
        r.SetTrackColor(track, color)
        
        local should_pin = GetProjectPinStatus(0)
        if should_pin then
            r.SetMediaTrackInfo_Value(track, "B_TCPPIN", 1)
        end
        
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
        
        local tf = io.open(TRACK_FILE, "r")
        if tf then
            local tc = tf:read("*all")
            tf:close()
            last_file_timestamp = tc:match('"timestamp":"([^"]+)"')
        end
        
        local saved_data = LoadTrackData()
        if saved_data and saved_data.chunk then
            local saved_normalized = NormalizeChunkForComparison(saved_data.chunk)
            if saved_normalized and state.last_normalized_chunk and saved_normalized ~= state.last_normalized_chunk then
                local saved_time = GetSavedDataTimestamp() or "unknown"
                local answer = r.MB(
                    "A newer saved version exists (" .. saved_time .. ").\n\nDo you want to load the saved version?\n\nYes = Load saved version\nNo = Keep current track (will overwrite saved)",
                    SCRIPT_NAME .. " - Sync Conflict",
                    4
                )
                if answer == 6 then
                    r.Undo_BeginBlock()
                    r.PreventUIRefresh(1)
                    SetTrackChunk(existing_track, saved_data.chunk)
                    state.last_chunk = saved_data.chunk
                    state.last_normalized_chunk = saved_normalized
                    r.PreventUIRefresh(-1)
                    r.Undo_EndBlock("Sync Indestructible Track", -1)
                    SetStatus("Track synced from saved data")
                else
                    SaveTrackData()
                    SetStatus("Current track saved (overwrote old)")
                end
            end
        end
        
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
                
                local tf = io.open(TRACK_FILE, "r")
                if tf then
                    local tc = tf:read("*all")
                    tf:close()
                    last_file_timestamp = tc:match('"timestamp":"([^"]+)"')
                end
                
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
        local _, new_track_chunk = r.GetTrackStateChunk(new_track, "", false)
        local new_guid = new_track_chunk:match("TRACKID ({[%x%-]+})")
        
        if new_guid then
            updated_chunk = updated_chunk:gsub("TRACKID {[%x%-]+}", "TRACKID " .. new_guid)
        end
        
        local success = SetTrackChunk(new_track, updated_chunk, false)
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
local last_file_timestamp = nil
local last_project_path = nil
local pending_change_time = nil
local pending_change_chunk = nil
local pending_tempo_sync = nil
local DEBOUNCE_DELAY = 0.5

local function CheckForExternalChanges()
    if pending_change_time then return end
    if not FileExists(TRACK_FILE) then return end
    
    local current_project_path = r.GetProjectPath() or ""
    if current_project_path ~= last_project_path then
        last_project_path = current_project_path
        last_file_timestamp = nil
    end
    
    local track = state.track_ptr
    if not track or not r.ValidatePtr(track, "MediaTrack*") then
        track = FindIndestructibleTrack()
        if not track then return end
        state.track_ptr = track
        state.track_guid = r.GetTrackGUID(track)
    end
    
    local f = io.open(TRACK_FILE, "r")
    if not f then return end
    local content = f:read("*all")
    f:close()
    
    local saved_timestamp = content:match('"timestamp":"([^"]+)"')
    if not saved_timestamp then return end
    
    if last_file_timestamp == nil then
        last_file_timestamp = saved_timestamp
        
        local saved_data = LoadTrackData()
        if saved_data and saved_data.chunk then
            local current_chunk = GetTrackChunk(track)
            if not current_chunk then return end
            
            local current_normalized = NormalizeChunkForComparison(current_chunk)
            local saved_normalized = NormalizeChunkForComparison(saved_data.chunk)
            
            local current_tempo = r.Master_GetTempo()
            local saved_tempo = saved_data.tempo
            
            if config.tempo_check_enabled and saved_tempo and math.abs(current_tempo - saved_tempo) > 0.01 then
                if config.remember_tempo_choice then
                    if config.tempo_choice == "time" then
                        r.Undo_BeginBlock()
                        r.PreventUIRefresh(1)
                        SetTrackChunk(track, saved_data.chunk)
                        state.last_chunk = saved_data.chunk
                        state.last_normalized_chunk = saved_normalized
                        AddToUndoHistory(saved_data.chunk)
                        r.PreventUIRefresh(-1)
                        r.Undo_EndBlock("Sync Indestructible Track", -1)
                        r.TrackList_AdjustWindows(false)
                        r.UpdateArrange()
                        SetStatus("Loaded (time-based)")
                    elseif config.tempo_choice == "beat" then
                        local adjusted_chunk = AdjustChunkToTempo(saved_data.chunk, saved_tempo, current_tempo)
                        r.Undo_BeginBlock()
                        r.PreventUIRefresh(1)
                        SetTrackChunk(track, adjusted_chunk)
                        state.last_chunk = adjusted_chunk
                        state.last_normalized_chunk = NormalizeChunkForComparison(adjusted_chunk)
                        AddToUndoHistory(adjusted_chunk)
                        r.PreventUIRefresh(-1)
                        r.Undo_EndBlock("Sync Indestructible Track (tempo adjusted)", -1)
                        r.TrackList_AdjustWindows(false)
                        r.UpdateArrange()
                        SaveTrackData()
                        SetStatus("Loaded (beat-based)")
                    else
                        state.last_chunk = current_chunk
                        state.last_normalized_chunk = current_normalized
                        SaveTrackData()
                        SetStatus("Cancelled (using current)")
                    end
                else
                    pending_tempo_sync = {
                        saved_data = saved_data,
                        saved_normalized = saved_normalized,
                        current_tempo = current_tempo,
                        saved_tempo = saved_tempo,
                        track = track
                    }
                    SetStatus("Tempo differs - confirm sync")
                end
            elseif saved_normalized ~= current_normalized then
                r.Undo_BeginBlock()
                r.PreventUIRefresh(1)
                SetTrackChunk(track, saved_data.chunk)
                state.last_chunk = saved_data.chunk
                state.last_normalized_chunk = saved_normalized
                AddToUndoHistory(saved_data.chunk)
                r.PreventUIRefresh(-1)
                r.Undo_EndBlock("Sync Indestructible Track", -1)
                r.TrackList_AdjustWindows(false)
                r.UpdateArrange()
                SetStatus("Synced from another project")
            else
                state.last_chunk = current_chunk
                state.last_normalized_chunk = current_normalized
            end
        end
        return
    end
    
    if saved_timestamp ~= last_file_timestamp then
        last_file_timestamp = saved_timestamp
        
        local saved_data = LoadTrackData()
        if saved_data and saved_data.chunk then
            local current_chunk = GetTrackChunk(track)
            if not current_chunk then return end
            
            local current_normalized = NormalizeChunkForComparison(current_chunk)
            local saved_normalized = NormalizeChunkForComparison(saved_data.chunk)
            
            local current_tempo = r.Master_GetTempo()
            local saved_tempo = saved_data.tempo
            
            if config.tempo_check_enabled and saved_tempo and math.abs(current_tempo - saved_tempo) > 0.01 then
                if config.remember_tempo_choice then
                    if config.tempo_choice == "time" then
                        r.Undo_BeginBlock()
                        r.PreventUIRefresh(1)
                        SetTrackChunk(track, saved_data.chunk)
                        state.last_chunk = saved_data.chunk
                        state.last_normalized_chunk = saved_normalized
                        AddToUndoHistory(saved_data.chunk)
                        r.PreventUIRefresh(-1)
                        r.Undo_EndBlock("Sync Indestructible Track", -1)
                        r.TrackList_AdjustWindows(false)
                        r.UpdateArrange()
                        SetStatus("Loaded (time-based)")
                    elseif config.tempo_choice == "beat" then
                        local adjusted_chunk = AdjustChunkToTempo(saved_data.chunk, saved_tempo, current_tempo)
                        r.Undo_BeginBlock()
                        r.PreventUIRefresh(1)
                        SetTrackChunk(track, adjusted_chunk)
                        state.last_chunk = adjusted_chunk
                        state.last_normalized_chunk = NormalizeChunkForComparison(adjusted_chunk)
                        AddToUndoHistory(adjusted_chunk)
                        r.PreventUIRefresh(-1)
                        r.Undo_EndBlock("Sync Indestructible Track (tempo adjusted)", -1)
                        r.TrackList_AdjustWindows(false)
                        r.UpdateArrange()
                        SaveTrackData()
                        SetStatus("Loaded (beat-based)")
                    else
                        state.last_chunk = current_chunk
                        state.last_normalized_chunk = current_normalized
                        SaveTrackData()
                        SetStatus("Cancelled (using current)")
                    end
                else
                    pending_tempo_sync = {
                        saved_data = saved_data,
                        saved_normalized = saved_normalized,
                        current_tempo = current_tempo,
                        saved_tempo = saved_tempo,
                        track = track
                    }
                    SetStatus("Tempo differs - confirm sync")
                end
            elseif saved_normalized ~= current_normalized then
                r.Undo_BeginBlock()
                r.PreventUIRefresh(1)
                SetTrackChunk(track, saved_data.chunk)
                state.last_chunk = saved_data.chunk
                state.last_normalized_chunk = saved_normalized
                
                AddToUndoHistory(saved_data.chunk)
                
                r.PreventUIRefresh(-1)
                r.Undo_EndBlock("Sync Indestructible Track", -1)
                r.TrackList_AdjustWindows(false)
                r.UpdateArrange()
                SetStatus("Synced from another project")
            else
                state.last_chunk = current_chunk
                state.last_normalized_chunk = current_normalized
            end
        end
    end
end

local function ProcessPendingChange()
    if not pending_change_time then return end
    
    local now = r.time_precise()
    if now - pending_change_time < DEBOUNCE_DELAY then return end
    
    local current_chunk = GetTrackChunk(state.track_ptr)
    if not current_chunk then 
        pending_change_time = nil
        pending_change_chunk = nil
        return 
    end
    
    local normalized_current = NormalizeChunkForComparison(current_chunk)
    
    AddToUndoHistory(current_chunk)
    state.last_chunk = current_chunk
    state.last_normalized_chunk = normalized_current
    last_file_timestamp = os.date("%Y-%m-%d %H:%M:%S")
    
    if SaveTrackData() then
        SetStatus("Auto-save: change saved (" .. os.date("%H:%M:%S") .. ")")
    else
        SetStatus("ERROR: Could not save change!", true)
    end
    
    pending_change_time = nil
    pending_change_chunk = nil
end

local function CheckForChanges()
    CheckForExternalChanges()
    ProcessPendingChange()
    
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
        pending_change_time = r.time_precise()
        pending_change_chunk = current_chunk
        state.last_chunk = current_chunk
        state.last_normalized_chunk = normalized_current
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

local main_hwnd = r.GetMainHwnd()
local arrange_hwnd = r.JS_Window_FindChildByID(main_hwnd, 0x3E8)

local function GetScreenScale()
    local OS = r.GetOS()
    if OS:find("Win") then
        local _, dpi = r.get_config_var_string("uiscale")
        return tonumber(dpi) or 1
    end
    return 1
end

local function GetArrangeWidth(use_ctx)
    if not arrange_hwnd then 
        arrange_hwnd = r.JS_Window_FindChildByID(main_hwnd, 0x3E8)
        if not arrange_hwnd then return 1000 end
    end
    local _, arr_left, arr_top, arr_right, arr_bottom = r.JS_Window_GetRect(arrange_hwnd)
    local native_width = arr_right - arr_left
    if use_ctx and r.ImGui_PointConvertNative then
        local conv_left = r.ImGui_PointConvertNative(use_ctx, arr_left, 0)
        local conv_right = r.ImGui_PointConvertNative(use_ctx, arr_right, 0)
        return math.floor(conv_right - conv_left)
    end
    return math.floor(native_width / GetScreenScale())
end

local function GetTrackTCPBounds(track, use_ctx)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then
        return nil
    end
    
    if not arrange_hwnd then 
        arrange_hwnd = r.JS_Window_FindChildByID(main_hwnd, 0x3E8)
        if not arrange_hwnd then return nil end
    end
    
    local screen_scale = GetScreenScale()
    
    local tcp_y = r.GetMediaTrackInfo_Value(track, "I_TCPY")
    local tcp_h = r.GetMediaTrackInfo_Value(track, "I_TCPH")
    local tcp_w = r.GetMediaTrackInfo_Value(track, "I_WNDW")
    
    if tcp_h < 10 then return nil end
    
    local _, arr_left, arr_top, arr_right, arr_bottom = r.JS_Window_GetRect(arrange_hwnd)
    local arr_height = arr_bottom - arr_top
    
    if tcp_y + tcp_h < 0 or tcp_y > arr_height then
        return nil
    end
    
    if tcp_w <= 0 then tcp_w = 200 end
    
    local _, main_left, _, _, _ = r.JS_Window_GetRect(main_hwnd)
    local tcp_total_width = arr_left - main_left
    
    local native_x = arr_left
    local native_y = arr_top + tcp_y
    
    local conv_x, conv_y
    if use_ctx and r.ImGui_PointConvertNative then
        conv_x, conv_y = r.ImGui_PointConvertNative(use_ctx, native_x, native_y)
    else
        conv_x = native_x / screen_scale
        conv_y = native_y / screen_scale
    end
    
    local conv_main_x
    if use_ctx and r.ImGui_PointConvertNative then
        conv_main_x, _ = r.ImGui_PointConvertNative(use_ctx, main_left, 0)
    else
        conv_main_x = main_left / screen_scale
    end
    
    local conv_h
    if use_ctx and r.ImGui_PointConvertNative then
        local _, h_scaled = r.ImGui_PointConvertNative(use_ctx, 0, tcp_h)
        local _, zero_scaled = r.ImGui_PointConvertNative(use_ctx, 0, 0)
        conv_h = h_scaled - zero_scaled
    else
        conv_h = tcp_h / screen_scale
    end
    
    local conv_w
    if use_ctx and r.ImGui_PointConvertNative then
        local w_scaled, _ = r.ImGui_PointConvertNative(use_ctx, tcp_w, 0)
        local zero_scaled, _ = r.ImGui_PointConvertNative(use_ctx, 0, 0)
        conv_w = w_scaled - zero_scaled
    else
        conv_w = tcp_w / screen_scale
    end
    
    local conv_tcp_total
    if use_ctx and r.ImGui_PointConvertNative then
        local w_scaled, _ = r.ImGui_PointConvertNative(use_ctx, tcp_total_width, 0)
        local zero_scaled, _ = r.ImGui_PointConvertNative(use_ctx, 0, 0)
        conv_tcp_total = w_scaled - zero_scaled
    else
        conv_tcp_total = tcp_total_width / screen_scale
    end
    
    return {
        x = conv_x,
        y = conv_y,
        w = conv_w,
        h = conv_h,
        tcp_x = conv_main_x,
        tcp_w = conv_tcp_total
    }
end

local compact_font = nil
local compact_menu_font = nil
local compact_shield_image = nil
local compact_ctx = nil

local function DrawCompactWidget()
    if not state.track_ptr or not r.ValidatePtr(state.track_ptr, "MediaTrack*") then
        return true
    end
    
    local icon_size = config.compact_icon_size or 28
    local font_size = math.max(10, math.floor(icon_size * 0.6))
    local menu_font_size = 13
    local padding_x = math.max(2, math.floor(icon_size * 0.2))
    local padding_y = math.max(1, math.floor(icon_size * 0.05))
    local rounding = math.max(2, math.floor(icon_size * 0.15))
    
    if not compact_ctx or not r.ImGui_ValidatePtr(compact_ctx, "ImGui_Context*") then
        compact_ctx = r.ImGui_CreateContext("TK_Indestructible_Compact")
        compact_font = nil
        compact_menu_font = nil
        compact_shield_image = nil
        state.last_compact_font_size = nil
    end
    
    if not compact_font or not r.ImGui_ValidatePtr(compact_font, "ImGui_Font*") or state.last_compact_font_size ~= font_size then
        compact_font = r.ImGui_CreateFont("Segoe UI", font_size)
        r.ImGui_Attach(compact_ctx, compact_font)
        state.last_compact_font_size = font_size
    end
    
    if not compact_menu_font or not r.ImGui_ValidatePtr(compact_menu_font, "ImGui_Font*") then
        compact_menu_font = r.ImGui_CreateFont("Segoe UI", menu_font_size)
        r.ImGui_Attach(compact_ctx, compact_menu_font)
    end
    
    if not compact_shield_image or not r.ImGui_ValidatePtr(compact_shield_image, "ImGui_Image*") then
        local img_path = SCRIPT_PATH .. "/ISHIELD.png"
        compact_shield_image = r.ImGui_CreateImage(img_path)
        if compact_shield_image then
            r.ImGui_Attach(compact_ctx, compact_shield_image)
        end
    end
    
    local bounds = GetTrackTCPBounds(state.track_ptr, compact_ctx)
    if not bounds then
        return true
    end
    
    local widget_x, widget_y
    
    if config.compact_lock_position and config.compact_locked_x and config.compact_locked_y then
        widget_x = bounds.tcp_x + config.compact_locked_x
        widget_y = bounds.y + config.compact_locked_y
    else
        widget_x = bounds.x + bounds.w + (config.compact_offset_x or 2)
        widget_y = bounds.y + (bounds.h - icon_size) / 2 + (config.compact_offset_y or 0)
    end
    
    r.ImGui_SetNextWindowPos(compact_ctx, widget_x, widget_y, r.ImGui_Cond_Always())
    
    if not config.compact_no_bg then
        r.ImGui_PushStyleColor(compact_ctx, r.ImGui_Col_WindowBg(), 0x000000DD)
        r.ImGui_PushStyleColor(compact_ctx, r.ImGui_Col_Border(), 0xFFFFFFFF)
    end
    r.ImGui_PushStyleColor(compact_ctx, r.ImGui_Col_Text(), 0xFFFFFFFF)
    r.ImGui_PushStyleVar(compact_ctx, r.ImGui_StyleVar_WindowRounding(), rounding)
    if not config.compact_no_bg then
        r.ImGui_PushStyleVar(compact_ctx, r.ImGui_StyleVar_WindowBorderSize(), 1)
    else
        r.ImGui_PushStyleVar(compact_ctx, r.ImGui_StyleVar_WindowBorderSize(), 0)
    end
    r.ImGui_PushStyleVar(compact_ctx, r.ImGui_StyleVar_WindowPadding(), padding_x, padding_y)
    r.ImGui_PushStyleVar(compact_ctx, r.ImGui_StyleVar_ItemSpacing(), math.floor(icon_size * 0.15), 0)
    
    r.ImGui_PushFont(compact_ctx, compact_font, font_size)
    
    local flags = r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_NoResize() | 
                  r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoCollapse() |
                  r.ImGui_WindowFlags_NoDocking() | r.ImGui_WindowFlags_NoMove() |
                  r.ImGui_WindowFlags_AlwaysAutoResize()
    if config.compact_no_bg then
        flags = flags | r.ImGui_WindowFlags_NoBackground()
    end
    
    local visible, open = r.ImGui_Begin(compact_ctx, "##compact_widget", true, flags)
    
    if visible then
        if compact_shield_image then
            r.ImGui_Image(compact_ctx, compact_shield_image, icon_size, icon_size)
            if not config.compact_icon_only then
                r.ImGui_SameLine(compact_ctx)
                local text_y = r.ImGui_GetCursorPosY(compact_ctx) + (icon_size - font_size) / 2 - padding_y
                r.ImGui_SetCursorPosY(compact_ctx, text_y)
                local display_name = config.track_name:gsub("🛡️%s*", ""):gsub("🛡%s*", "")
                r.ImGui_Text(compact_ctx, display_name)
            end
        end
        
        if r.ImGui_IsItemHovered(compact_ctx) and r.ImGui_IsMouseClicked(compact_ctx, 1) then
            r.ImGui_OpenPopup(compact_ctx, "compact_menu")
        end
        
        if r.ImGui_IsWindowHovered(compact_ctx) and r.ImGui_IsMouseClicked(compact_ctx, 1) then
            r.ImGui_OpenPopup(compact_ctx, "compact_menu")
        end
        
        if r.ImGui_IsWindowHovered(compact_ctx) and r.ImGui_IsMouseDoubleClicked(compact_ctx, 0) then
            config.compact_mode = false
            SaveConfig()
        end
        
        if r.ImGui_BeginPopup(compact_ctx, "compact_menu") then
            r.ImGui_PushFont(compact_ctx, compact_menu_font, 13)
            if r.ImGui_MenuItem(compact_ctx, "Save Now") then
                SaveTrackData()
                SetStatus("Saved manually")
            end
            if r.ImGui_MenuItem(compact_ctx, "Save Snapshot...") then
                state.show_snapshot_save = true
                config.compact_mode = false
                SaveConfig()
            end
            if r.ImGui_MenuItem(compact_ctx, "Copy to Project") then
                CopyTrackToProject()
            end
            r.ImGui_Separator(compact_ctx)
            if r.ImGui_MenuItem(compact_ctx, "Snapshots") then
                ScanSnapshots()
                state.show_snapshot_list = true
                config.compact_mode = false
                SaveConfig()
            end
            if r.ImGui_MenuItem(compact_ctx, "Auto-Saves") then
                ScanBackups()
                state.show_backup_list = true
                config.compact_mode = false
                SaveConfig()
            end
            r.ImGui_Separator(compact_ctx)
            if r.ImGui_MenuItem(compact_ctx, "Undo", nil, false, state.undo_index > 1) then
                UndoTrack()
            end
            if r.ImGui_MenuItem(compact_ctx, "Redo", nil, false, state.undo_index < #state.undo_history) then
                RedoTrack()
            end
            r.ImGui_Separator(compact_ctx)
            if r.ImGui_MenuItem(compact_ctx, "Full UI") then
                config.compact_mode = false
                SaveConfig()
            end
            r.ImGui_PopFont(compact_ctx)
            r.ImGui_EndPopup(compact_ctx)
        end
        
        r.ImGui_End(compact_ctx)
    end
    
    r.ImGui_PopFont(compact_ctx)
    r.ImGui_PopStyleVar(compact_ctx, 4)
    if not config.compact_no_bg then
        r.ImGui_PopStyleColor(compact_ctx, 3)
    else
        r.ImGui_PopStyleColor(compact_ctx, 1)
    end
    
    return open
end

local function LoadShieldImage()
    if shield_image and r.ImGui_ValidatePtr(shield_image, "ImGui_Image*") then return end
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
    
    local window_height = r.ImGui_GetWindowHeight(ctx)
    local footer_height = 55
    local content_end_y = window_height - footer_height
    
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
    
    local content_start_y = r.ImGui_GetCursorPosY(ctx)
    local content_height = content_end_y - content_start_y - 10
    if content_height < 50 then content_height = 50 end
    
    if state.show_backup_list then
        r.ImGui_Text(ctx, "Auto-Saves (" .. #available_backups .. " available)")
        if r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Automatic backups of recent changes (rotates, keeps last " .. config.auto_backup_count .. ")")
        end
        r.ImGui_Spacing(ctx)
        
        local list_height = content_height - 50
        if list_height < 30 then list_height = 30 end
        
        if r.ImGui_BeginChild(ctx, "backup_list", -1, list_height, 1) then
            if #available_backups == 0 then
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.text_dim)
                r.ImGui_Text(ctx, "No auto-saves found")
                r.ImGui_PopStyleColor(ctx)
            else
                for i, backup in ipairs(available_backups) do
                    r.ImGui_PushID(ctx, i)
                    if r.ImGui_Selectable(ctx, backup.display, false) then
                        if LoadBackup(backup) then
                            state.show_backup_list = false
                        end
                    end
                    if r.ImGui_IsItemHovered(ctx) then
                        r.ImGui_SetTooltip(ctx, "Click to restore this auto-save")
                    end
                    r.ImGui_PopID(ctx)
                end
            end
            r.ImGui_EndChild(ctx)
        end
        
        if r.ImGui_Button(ctx, "< Back", -1, 0) then
            state.show_backup_list = false
        end
    elseif state.show_snapshot_list then
        r.ImGui_Text(ctx, "Snapshots (" .. #available_snapshots .. " saved)")
        if r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Manually saved versions - kept until you delete them")
        end
        r.ImGui_Spacing(ctx)
        
        local list_height = content_height - 80
        if list_height < 30 then list_height = 30 end
        
        if r.ImGui_BeginChild(ctx, "snapshot_list", -1, list_height, 1) then
            if #available_snapshots == 0 then
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.text_dim)
                r.ImGui_Text(ctx, "No snapshots saved yet")
                r.ImGui_Text(ctx, "Use 'Save Snapshot' to create one")
                r.ImGui_PopStyleColor(ctx)
            else
                for i, snapshot in ipairs(available_snapshots) do
                    r.ImGui_PushID(ctx, i)
                    r.ImGui_Text(ctx, snapshot.name)
                    r.ImGui_SameLine(ctx)
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.text_dim)
                    r.ImGui_Text(ctx, "(" .. snapshot.timestamp .. ")")
                    r.ImGui_PopStyleColor(ctx)
                    
                    if r.ImGui_Button(ctx, "Load##" .. i, 50, 0) then
                        if LoadSnapshot(snapshot) then
                            state.show_snapshot_list = false
                        end
                    end
                    if r.ImGui_IsItemHovered(ctx) then
                        r.ImGui_SetTooltip(ctx, "Restore track to this saved state")
                    end
                    r.ImGui_SameLine(ctx)
                    if r.ImGui_Button(ctx, "Delete##" .. i, 50, 0) then
                        DeleteSnapshot(snapshot)
                    end
                    if r.ImGui_IsItemHovered(ctx) then
                        r.ImGui_SetTooltip(ctx, "Permanently remove this snapshot")
                    end
                    r.ImGui_Separator(ctx)
                    r.ImGui_PopID(ctx)
                end
            end
            r.ImGui_EndChild(ctx)
        end
        
        local has_track = state.track_ptr and r.ValidatePtr(state.track_ptr, "MediaTrack*")
        if not has_track then r.ImGui_BeginDisabled(ctx) end
        if r.ImGui_Button(ctx, "Save New Snapshot", -1, 0) then
            state.show_snapshot_list = false
            state.show_snapshot_save = true
            state.snapshot_name_input = ""
        end
        if r.ImGui_IsItemHovered(ctx) and has_track then
            r.ImGui_SetTooltip(ctx, "Save current track state with a name")
        end
        if not has_track then r.ImGui_EndDisabled(ctx) end
        
        if r.ImGui_Button(ctx, "< Back", -1, 0) then
            state.show_snapshot_list = false
        end
    elseif state.show_snapshot_save then
        r.ImGui_Text(ctx, "Save Snapshot")
        r.ImGui_Spacing(ctx)
        r.ImGui_TextWrapped(ctx, "Give your snapshot a descriptive name so you can recognize it later.")
        r.ImGui_Spacing(ctx)
        
        r.ImGui_Text(ctx, "Name:")
        r.ImGui_SetNextItemWidth(ctx, -1)
        local changed, new_val = r.ImGui_InputText(ctx, "##snapshot_name", state.snapshot_name_input)
        if changed then state.snapshot_name_input = new_val end
        
        if r.ImGui_IsItemFocused(ctx) and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Enter()) and state.snapshot_name_input ~= "" then
            if SaveSnapshot(state.snapshot_name_input) then
                ScanSnapshots()
                state.show_snapshot_save = false
                state.show_snapshot_list = true
            end
        end
        
        r.ImGui_Spacing(ctx)
        
        local name_empty = state.snapshot_name_input == ""
        if name_empty then r.ImGui_BeginDisabled(ctx) end
        if r.ImGui_Button(ctx, "Save", -1, 0) then
            if SaveSnapshot(state.snapshot_name_input) then
                ScanSnapshots()
                state.show_snapshot_save = false
                state.show_snapshot_list = true
            end
        end
        if name_empty then r.ImGui_EndDisabled(ctx) end
        
        if r.ImGui_Button(ctx, "Cancel", -1, 0) then
            state.show_snapshot_save = false
            state.show_snapshot_list = true
        end
    elseif state.show_undo_list then
        r.ImGui_Text(ctx, "Undo History (" .. state.undo_index .. "/" .. #state.undo_history .. ")")
        r.ImGui_Spacing(ctx)
        
        local list_height = content_height - 50
        if list_height < 30 then list_height = 30 end
        
        if r.ImGui_BeginChild(ctx, "undo_list", -1, list_height, 1) then
            for i = #state.undo_history, 1, -1 do
                local entry = state.undo_history[i]
                local is_current = (i == state.undo_index)
                local desc = entry.description or "Track modified"
                local label = string.format("%s  %s", entry.timestamp, desc)
                
                if is_current then
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.accent)
                    label = "> " .. label
                elseif i > state.undo_index then
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.text_dim)
                end
                
                r.ImGui_PushID(ctx, i)
                if r.ImGui_Selectable(ctx, label, is_current) then
                    JumpToUndoState(i)
                end
                r.ImGui_PopID(ctx)
                
                if is_current or i > state.undo_index then
                    r.ImGui_PopStyleColor(ctx)
                end
            end
            r.ImGui_EndChild(ctx)
        end
        
        local button_width = (WINDOW_WIDTH - 30) / 2
        if r.ImGui_Button(ctx, "< Back", button_width, 0) then
            state.show_undo_list = false
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Clear History", button_width, 0) then
            local current_entry = state.undo_history[state.undo_index]
            local current_chunk = current_entry and current_entry.chunk or nil
            state.undo_history = {}
            state.undo_index = 0
            if current_chunk then
                AddToUndoHistory(current_chunk)
            end
            SetStatus("Undo history cleared")
        end
    else
        if r.ImGui_BeginChild(ctx, "main_content", -1, content_height, 0) then
            local undo_disabled = state.undo_index <= 1
            local redo_disabled = state.undo_index >= #state.undo_history
            
            local button_width = (WINDOW_WIDTH - 30) / 3
            
            if undo_disabled then r.ImGui_BeginDisabled(ctx) end
            if r.ImGui_Button(ctx, "< Undo##track", button_width, 0) then
                UndoTrack()
            end
            if undo_disabled then r.ImGui_EndDisabled(ctx) end
            
            r.ImGui_SameLine(ctx)
            
            if r.ImGui_Button(ctx, state.undo_index .. "/" .. #state.undo_history .. "##list", button_width, 0) then
                state.show_undo_list = true
            end
            if r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, "Show undo history list")
            end
            
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
            
            if r.ImGui_Button(ctx, "Snapshots", -1, 0) then
                ScanSnapshots()
                state.show_snapshot_list = true
            end
            if r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, "Manually saved versions you can restore anytime")
            end
            
            if r.ImGui_Button(ctx, "Auto-Saves", -1, 0) then
                ScanBackups()
                state.show_backup_list = true
            end
            if r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, "Automatic backups of recent changes")
            end
            
            r.ImGui_Separator(ctx)
            
            if r.ImGui_Button(ctx, "Compact Mode", -1, 0) then
                config.compact_mode = true
                SaveConfig()
            end
            if r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, "Show minimal overlay on track (experimental)")
            end
            
            r.ImGui_EndChild(ctx)
        end
    end
    
    r.ImGui_SetCursorPosY(ctx, window_height - footer_height)
    r.ImGui_Separator(ctx)
    DrawStatusBar()
end

local function DrawSettingsUI()
    r.ImGui_Text(ctx, "SETTINGS")
    r.ImGui_Separator(ctx)
    
    local window_height = r.ImGui_GetWindowHeight(ctx)
    local content_height = window_height - 100
    if content_height < 50 then content_height = 50 end
    
    if r.ImGui_BeginTabBar(ctx, "settings_tabs") then
        if r.ImGui_BeginTabItem(ctx, "General") then
            if r.ImGui_BeginChild(ctx, "general_content", -1, content_height - 30, 0) then
                local changed, new_val
                
                r.ImGui_Text(ctx, "Track name:")
                local old_name = config.track_name
                changed, new_val = r.ImGui_InputText(ctx, "##trackname", config.track_name)
                if changed then 
                    config.track_name = new_val
                    if state.track_ptr and r.ValidatePtr(state.track_ptr, "MediaTrack*") then
                        r.GetSetMediaTrackInfo_String(state.track_ptr, "P_NAME", new_val, true)
                    end
                end
                
                r.ImGui_Text(ctx, "Check interval (sec):")
                changed, new_val = r.ImGui_SliderDouble(ctx, "##interval", config.check_interval, 0.5, 5.0, "%.1f")
                if changed then config.check_interval = new_val end
                
                r.ImGui_Text(ctx, "Max undo history:")
                changed, new_val = r.ImGui_SliderInt(ctx, "##maxundo", config.max_undo_history, 10, 200)
                if changed then config.max_undo_history = new_val end
                
                r.ImGui_Text(ctx, "Auto-saves to keep:")
                changed, new_val = r.ImGui_SliderInt(ctx, "##backups", config.auto_backup_count, 1, 20)
                if changed then config.auto_backup_count = new_val end
                if r.ImGui_IsItemHovered(ctx) then
                    r.ImGui_SetTooltip(ctx, "Number of automatic backups to keep (oldest are deleted)")
                end
                
                changed, new_val = r.ImGui_Checkbox(ctx, "Show notifications", config.show_notifications)
                if changed then config.show_notifications = new_val end
                
                changed, new_val = r.ImGui_Checkbox(ctx, "Auto-load on start", config.auto_load_on_start)
                if changed then config.auto_load_on_start = new_val end
                
                changed, new_val = r.ImGui_Checkbox(ctx, "Warn on tempo mismatch", config.tempo_check_enabled)
                if changed then config.tempo_check_enabled = new_val end
                
                if config.tempo_check_enabled then
                    r.ImGui_Indent(ctx)
                    changed, new_val = r.ImGui_Checkbox(ctx, "Remember choice", config.remember_tempo_choice)
                    if changed then config.remember_tempo_choice = new_val end
                    if r.ImGui_IsItemHovered(ctx) then
                        r.ImGui_SetTooltip(ctx, "Auto-apply chosen method without asking")
                    end
                    
                    if config.remember_tempo_choice then
                        if r.ImGui_RadioButton(ctx, "Time##tm", config.tempo_choice == "time") then
                            config.tempo_choice = "time"
                        end
                        if r.ImGui_IsItemHovered(ctx) then
                            r.ImGui_SetTooltip(ctx, "Keep items at same time positions (seconds)")
                        end
                        r.ImGui_SameLine(ctx)
                        if r.ImGui_RadioButton(ctx, "Beat##tm", config.tempo_choice == "beat") then
                            config.tempo_choice = "beat"
                        end
                        if r.ImGui_IsItemHovered(ctx) then
                            r.ImGui_SetTooltip(ctx, "Adjust positions to keep items at same beats")
                        end
                        r.ImGui_SameLine(ctx)
                        if r.ImGui_RadioButton(ctx, "Skip##tm", config.tempo_choice == "cancel") then
                            config.tempo_choice = "cancel"
                        end
                        if r.ImGui_IsItemHovered(ctx) then
                            r.ImGui_SetTooltip(ctx, "Keep current track, ignore saved version")
                        end
                    end
                    r.ImGui_Unindent(ctx)
                end
                
                r.ImGui_EndChild(ctx)
            end
            r.ImGui_EndTabItem(ctx)
        end
        
        if r.ImGui_BeginTabItem(ctx, "Display") then
            if r.ImGui_BeginChild(ctx, "display_content", -1, content_height - 30, 0) then
                local has_track = state.track_ptr and r.ValidatePtr(state.track_ptr, "MediaTrack*")
                
                if has_track then
                    r.ImGui_Text(ctx, "Track placement:")
                    local track_idx = math.floor(r.GetMediaTrackInfo_Value(state.track_ptr, "IP_TRACKNUMBER") - 1)
                    local track_count = r.CountTracks(0)
                    local is_at_top = (track_idx == 0)
                    local is_at_bottom = (track_idx == track_count - 1)
                    
                    local is_pinned = GetProjectPinStatus(0)
                    
                    r.ImGui_Text(ctx, "Position:")
                    r.ImGui_SameLine(ctx)
                    
                    local clicked_top = r.ImGui_RadioButton(ctx, "Top##pos", is_at_top)
                    if r.ImGui_IsItemHovered(ctx) then
                        r.ImGui_SetTooltip(ctx, "Move track to top of track list")
                    end
                    r.ImGui_SameLine(ctx)
                    local clicked_bottom = r.ImGui_RadioButton(ctx, "Bottom##pos", is_at_bottom)
                    if r.ImGui_IsItemHovered(ctx) then
                        r.ImGui_SetTooltip(ctx, "Move track to bottom of track list")
                    end
                    
                    if clicked_top and not is_at_top then
                        r.Undo_BeginBlock()
                        r.PreventUIRefresh(1)
                        r.SetOnlyTrackSelected(state.track_ptr)
                        r.ReorderSelectedTracks(0, 0)
                        r.PreventUIRefresh(-1)
                        r.Undo_EndBlock("Move Indestructible Track to top", -1)
                        r.TrackList_AdjustWindows(false)
                        SetStatus("Track moved to top")
                    end
                    
                    if clicked_bottom and not is_at_bottom then
                        r.Undo_BeginBlock()
                        r.PreventUIRefresh(1)
                        r.SetOnlyTrackSelected(state.track_ptr)
                        r.ReorderSelectedTracks(track_count, 0)
                        r.PreventUIRefresh(-1)
                        r.Undo_EndBlock("Move Indestructible Track to bottom", -1)
                        r.TrackList_AdjustWindows(false)
                        SetStatus("Track moved to bottom")
                    end
                    
                    local pin_changed, pin_val = r.ImGui_Checkbox(ctx, "Pin track (TCP only)", is_pinned)
                    if r.ImGui_IsItemHovered(ctx) then
                        r.ImGui_SetTooltip(ctx, "Keep track pinned at its position in TCP when scrolling")
                    end
                    
                    if pin_changed then
                        local new_pin = not is_pinned
                        SetProjectPinStatus(0, new_pin)
                        r.SetMediaTrackInfo_Value(state.track_ptr, "B_TCPPIN", new_pin and 1 or 0)
                        r.TrackList_AdjustWindows(false)
                        r.UpdateArrange()
                        if new_pin then
                            SetStatus("Track pinned")
                        else
                            SetStatus("Track unpinned")
                        end
                    end
                    
                    r.ImGui_Spacing(ctx)
                    r.ImGui_Separator(ctx)
                    r.ImGui_Spacing(ctx)
                    r.ImGui_Text(ctx, "Compact Mode:")
                    local compact_changed, compact_val = r.ImGui_Checkbox(ctx, "Compact TCP overlay", config.compact_mode)
                    if r.ImGui_IsItemHovered(ctx) then
                        r.ImGui_SetTooltip(ctx, "Show minimal widget on track")
                    end
                    if compact_changed then
                        config.compact_mode = compact_val
                        SaveConfig()
                    end
                    
                    r.ImGui_Indent(ctx)
                    local changed_icon, new_icon = r.ImGui_Checkbox(ctx, "Icon only", config.compact_icon_only)
                    if changed_icon then
                        config.compact_icon_only = new_icon
                        SaveConfig()
                    end
                    local changed_bg, new_bg = r.ImGui_Checkbox(ctx, "No background", config.compact_no_bg)
                    if changed_bg then
                        config.compact_no_bg = new_bg
                        SaveConfig()
                    end
                    r.ImGui_Unindent(ctx)
                    
                    r.ImGui_Text(ctx, "Icon size:")
                    local size_changed, size_val = r.ImGui_SliderInt(ctx, "##iconsize", config.compact_icon_size or 28, 16, 64)
                    if size_changed then
                        config.compact_icon_size = size_val
                        SaveConfig()
                    end
                    
                    r.ImGui_Text(ctx, "Overlay offset X:")
                    local full_tcp_width = 0
                    local icon_size = config.compact_icon_size or 28
                    if state.track_ptr and r.ValidatePtr(state.track_ptr, "MediaTrack*") then
                        local bounds = GetTrackTCPBounds(state.track_ptr, ctx)
                        if bounds then 
                            full_tcp_width = bounds.w + (bounds.tcp_w or 0)
                        end
                    end
                    local max_offset = GetArrangeWidth(ctx) - 150
                    if max_offset < 100 then max_offset = 1000 end
                    local min_offset = -(full_tcp_width + icon_size + 10)
                    
                    r.ImGui_SetNextItemWidth(ctx, -60)
                    local offset_changed, offset_val = r.ImGui_SliderInt(ctx, "##compactoffset", config.compact_offset_x or 2, min_offset, max_offset)
                    if offset_changed then 
                        config.compact_offset_x = offset_val 
                        SaveConfig()
                    end
                    r.ImGui_SameLine(ctx)
                    if r.ImGui_Button(ctx, "-##xminus", 25, 0) then
                        config.compact_offset_x = (config.compact_offset_x or 2) - 1
                        SaveConfig()
                    end
                    r.ImGui_SameLine(ctx)
                    if r.ImGui_Button(ctx, "+##xplus", 25, 0) then
                        config.compact_offset_x = (config.compact_offset_x or 2) + 1
                        SaveConfig()
                    end
                    
                    r.ImGui_Text(ctx, "Overlay offset Y:")
                    local track_height = 0
                    if state.track_ptr and r.ValidatePtr(state.track_ptr, "MediaTrack*") then
                        local bounds = GetTrackTCPBounds(state.track_ptr, ctx)
                        if bounds then track_height = bounds.h end
                    end
                    local y_range = math.max(50, math.floor((track_height - icon_size) / 2) + 20)
                    
                    r.ImGui_SetNextItemWidth(ctx, -60)
                    local offset_y_changed, offset_y_val = r.ImGui_SliderInt(ctx, "##compactoffsety", config.compact_offset_y or 0, -y_range, y_range)
                    if offset_y_changed then 
                        config.compact_offset_y = offset_y_val 
                        SaveConfig()
                    end
                    r.ImGui_SameLine(ctx)
                    if r.ImGui_Button(ctx, "-##yminus", 25, 0) then
                        config.compact_offset_y = (config.compact_offset_y or 0) - 1
                        SaveConfig()
                    end
                    r.ImGui_SameLine(ctx)
                    if r.ImGui_Button(ctx, "+##yplus", 25, 0) then
                        config.compact_offset_y = (config.compact_offset_y or 0) + 1
                        SaveConfig()
                    end
                    
                    r.ImGui_Spacing(ctx)
                    local lock_changed, lock_val = r.ImGui_Checkbox(ctx, "Lock position", config.compact_lock_position)
                    if r.ImGui_IsItemHovered(ctx) then
                        r.ImGui_SetTooltip(ctx, "Lock current position absolutely within TCP")
                    end
                    if lock_changed then
                        config.compact_lock_position = lock_val
                        if lock_val then
                            local bounds = GetTrackTCPBounds(state.track_ptr, ctx)
                            if bounds then
                                local current_x = bounds.x + bounds.w + (config.compact_offset_x or 2)
                                local current_y = bounds.y + (bounds.h - (config.compact_icon_size or 28)) / 2 + (config.compact_offset_y or 0)
                                config.compact_locked_x = current_x - bounds.tcp_x
                                config.compact_locked_y = current_y - bounds.y
                            end
                        else
                            config.compact_locked_x = nil
                            config.compact_locked_y = nil
                        end
                        SaveConfig()
                    end
                    
                    r.ImGui_Spacing(ctx)
                    local preview_changed, preview_val = r.ImGui_Checkbox(ctx, "Show preview", state.preview_compact)
                    if preview_changed then
                        state.preview_compact = preview_val
                    end
                else
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.text_dim)
                    r.ImGui_Text(ctx, "No track found")
                    r.ImGui_PopStyleColor(ctx)
                    
                    r.ImGui_Spacing(ctx)
                    if r.ImGui_Button(ctx, "Create Indestructible Track", -1, 0) then
                        LoadOrCreateTrack()
                        state.is_monitoring = true
                    end
                end
                
                r.ImGui_EndChild(ctx)
            end
            r.ImGui_EndTabItem(ctx)
        end
        
        r.ImGui_EndTabBar(ctx)
    end
    
    r.ImGui_Separator(ctx)
    
    if r.ImGui_Button(ctx, "Save and Close", -1, 0) then
        SaveConfig()
        state.show_settings = false
        SetStatus("Settings saved")
    end
    
    if r.ImGui_Button(ctx, "Cancel##settings", -1, 0) then
        LoadConfig()
        state.show_settings = false
    end
end

local function loop()
    if not r.ImGui_ValidatePtr(ctx, "ImGui_Context*") then
        ctx = r.ImGui_CreateContext(SCRIPT_NAME)
        font_loaded = false
        shield_image = nil
    end
    
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
    
    if config.compact_mode then
        local keep_running = DrawCompactWidget()
        if keep_running then
            r.defer(loop)
        else
            SaveConfig()
            RemoveLockFile()
        end
        return
    end
    
    if state.preview_compact then
        DrawCompactWidget()
    end
    
    ApplyTheme()
    r.ImGui_PushFont(ctx, main_font, 13)
    
    local window_flags = r.ImGui_WindowFlags_NoCollapse() | r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
    r.ImGui_SetNextWindowSizeConstraints(ctx, WINDOW_WIDTH, MIN_WINDOW_HEIGHT, WINDOW_WIDTH, 800)
    
    local visible, open = r.ImGui_Begin(ctx, SCRIPT_NAME, true, window_flags)
    
    if visible then
        if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape()) and not state.show_close_warning then
            if state.track_ptr and r.ValidatePtr(state.track_ptr, "MediaTrack*") then
                state.show_close_warning = true
            else
                open = false
            end
        end
        
        if state.show_close_warning then
            local center_x, center_y = r.ImGui_GetWindowPos(ctx)
            center_x = center_x + WINDOW_WIDTH / 2
            center_y = center_y + WINDOW_HEIGHT / 2
            r.ImGui_SetNextWindowPos(ctx, center_x, center_y, r.ImGui_Cond_Appearing(), 0.5, 0.5)
            r.ImGui_SetNextWindowSize(ctx, 320, 0, r.ImGui_Cond_Appearing())
            
            local popup_visible, popup_open = r.ImGui_Begin(ctx, "Close Script?###closepopup", true, r.ImGui_WindowFlags_NoCollapse() | r.ImGui_WindowFlags_NoResize())
            if popup_visible then
                r.ImGui_Text(ctx, "The Indestructible Track is still")
                r.ImGui_Text(ctx, "in this project.")
                r.ImGui_Spacing(ctx)
                r.ImGui_Text(ctx, "Track data is safely saved.")
                r.ImGui_Spacing(ctx)
                r.ImGui_Separator(ctx)
                r.ImGui_Spacing(ctx)
                
                if r.ImGui_Button(ctx, "Keep Track", 90, 25) then
                    state.close_action = "keep"
                    state.show_close_warning = false
                end
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "Remove Track", 100, 25) then
                    state.close_action = "remove"
                    state.show_close_warning = false
                end
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "Cancel", 70, 25) then
                    state.show_close_warning = false
                    state.close_action = nil
                end
                r.ImGui_End(ctx)
            end
            if not popup_open then
                state.show_close_warning = false
                state.close_action = nil
            end
        end
        
        if pending_tempo_sync then
            local center_x, center_y = r.ImGui_GetWindowPos(ctx)
            center_x = center_x + WINDOW_WIDTH / 2
            center_y = center_y + WINDOW_HEIGHT / 2
            r.ImGui_SetNextWindowPos(ctx, center_x, center_y, r.ImGui_Cond_Appearing(), 0.5, 0.5)
            r.ImGui_SetNextWindowSize(ctx, 360, 0, r.ImGui_Cond_Appearing())
            
            local tempo_popup_visible, tempo_popup_open = r.ImGui_Begin(ctx, "Tempo Mismatch###tempopopup", true, r.ImGui_WindowFlags_NoCollapse() | r.ImGui_WindowFlags_NoResize())
            if tempo_popup_visible then
                r.ImGui_TextColored(ctx, COLORS.warning, "Tempo mismatch detected")
                r.ImGui_Spacing(ctx)
                r.ImGui_Text(ctx, string.format("Current project: %.2f BPM", pending_tempo_sync.current_tempo))
                r.ImGui_Text(ctx, string.format("Saved track: %.2f BPM", pending_tempo_sync.saved_tempo))
                r.ImGui_Spacing(ctx)
                r.ImGui_TextWrapped(ctx, "How should item positions be handled?")
                r.ImGui_Spacing(ctx)
                r.ImGui_Separator(ctx)
                r.ImGui_Spacing(ctx)
                
                local btn_width = 100
                local spacing = r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing())
                local total_width = btn_width * 3 + spacing * 2
                local start_x = (360 - total_width) / 2
                r.ImGui_SetCursorPosX(ctx, start_x)
                
                if r.ImGui_Button(ctx, "Time-based", btn_width, 25) then
                    local pts = pending_tempo_sync
                    r.Undo_BeginBlock()
                    r.PreventUIRefresh(1)
                    SetTrackChunk(pts.track, pts.saved_data.chunk)
                    state.last_chunk = pts.saved_data.chunk
                    state.last_normalized_chunk = pts.saved_normalized
                    AddToUndoHistory(pts.saved_data.chunk)
                    r.PreventUIRefresh(-1)
                    r.Undo_EndBlock("Sync Indestructible Track", -1)
                    r.TrackList_AdjustWindows(false)
                    r.UpdateArrange()
                    SetStatus("Loaded (time-based)")
                    pending_tempo_sync = nil
                end
                if r.ImGui_IsItemHovered(ctx) then
                    r.ImGui_SetTooltip(ctx, "Keep items at same time positions (seconds)")
                end
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "Beat-based", btn_width, 25) then
                    local pts = pending_tempo_sync
                    local adjusted_chunk = AdjustChunkToTempo(pts.saved_data.chunk, pts.saved_tempo, pts.current_tempo)
                    r.Undo_BeginBlock()
                    r.PreventUIRefresh(1)
                    SetTrackChunk(pts.track, adjusted_chunk)
                    state.last_chunk = adjusted_chunk
                    state.last_normalized_chunk = NormalizeChunkForComparison(adjusted_chunk)
                    AddToUndoHistory(adjusted_chunk)
                    r.PreventUIRefresh(-1)
                    r.Undo_EndBlock("Sync Indestructible Track (tempo adjusted)", -1)
                    r.TrackList_AdjustWindows(false)
                    r.UpdateArrange()
                    SaveTrackData()
                    SetStatus("Loaded (beat-based)")
                    pending_tempo_sync = nil
                end
                if r.ImGui_IsItemHovered(ctx) then
                    r.ImGui_SetTooltip(ctx, "Adjust positions to keep items at same beats")
                end
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "Cancel", btn_width, 25) then
                    state.last_chunk = GetTrackChunk(pending_tempo_sync.track)
                    state.last_normalized_chunk = NormalizeChunkForComparison(state.last_chunk)
                    SaveTrackData()
                    pending_tempo_sync = nil
                    SetStatus("Cancelled")
                end
                if r.ImGui_IsItemHovered(ctx) then
                    r.ImGui_SetTooltip(ctx, "Keep current track, save as new state")
                end
                r.ImGui_End(ctx)
            end
            if not tempo_popup_open then
                pending_tempo_sync = nil
            end
        end
        
        if state.close_action then
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
            if state.close_action == "remove" then
                local track_idx = r.GetMediaTrackInfo_Value(state.track_ptr, "IP_TRACKNUMBER") - 1
                if track_idx >= 0 then
                    r.DeleteTrack(state.track_ptr)
                end
            end
        end
        SaveConfig()
    end
end

local function OnExit()
    if state.close_action then
        RemoveLockFile()
        return
    end
    
    local track = FindIndestructibleTrack()
    if track then
        SaveTrackData()
        local answer = r.MB(
            "The Indestructible Track is still in this project.\nTrack data is safely saved.\n\nRemove track from project?",
            SCRIPT_NAME,
            4
        )
        if answer == 6 then
            r.DeleteTrack(track)
        end
    end
    RemoveLockFile()
    SaveConfig()
end

local function Init()
    EnsureDirectories()
    LoadConfig()
    
    local lock_info = CheckLockFile()
    if lock_info then
        local answer = r.MB(
            "The Indestructible Track may be open in another project:\n\n" ..
            "Project: " .. (lock_info.project or "Unknown") .. "\n" ..
            "Since: " .. (lock_info.time or "Unknown") .. "\n\n" ..
            "Continue anyway? (Changes may conflict)",
            SCRIPT_NAME .. " - Already Running?",
            4
        )
        if answer ~= 6 then
            return
        end
    end
    
    CreateLockFile()
    
    local track = LoadOrCreateTrack()
    if track then
        state.is_monitoring = true
        state.last_project_state = r.GetProjectStateChangeCount(0)
    end
    
    r.atexit(OnExit)
    r.defer(loop)
end

Init()
