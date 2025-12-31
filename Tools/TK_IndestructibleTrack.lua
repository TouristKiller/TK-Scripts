-- @description TK Indestructible Track
-- @author TouristKiller
-- @version 3.4
-- @changelog:
--   + Configurable track name prefix (enable/disable and custom text)
--   + External toggle scripts for toolbar buttons with sync support
--   + Toolbar buttons reflect current state when toggled via checkbox or script

-------------------------------------------------------------------
local r = reaper

local SCRIPT_NAME = "TK Indestructible Track"
local COMMAND_ID = nil

local function GetScriptVersion()
    local file = io.open(debug.getinfo(1, "S").source:match("@?(.*)") or "", "r")
    if file then
        for i = 1, 10 do
            local line = file:read("*l")
            if line then
                local version = line:match("@version%s+(.+)")
                if version then
                    file:close()
                    return version
                end
            end
        end
        file:close()
    end
    return "?"
end

local SCRIPT_VERSION = GetScriptVersion()

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
    active_profile = 1,
    profiles = {
        {
            name = "Indestructible 1",
            track_color = 0x1E5A8A,
            data_file = "TK_IT_Profile1.json",
            enabled = true
        },
        {
            name = "Indestructible 2",
            track_color = 0x8A5A1E,
            data_file = "TK_IT_Profile2.json",
            enabled = false
        },
        {
            name = "Indestructible 3",
            track_color = 0x5A8A1E,
            data_file = "TK_IT_Profile3.json",
            enabled = false
        },
        {
            name = "Indestructible 4",
            track_color = 0x8A1E5A,
            data_file = "TK_IT_Profile4.json",
            enabled = false
        }
    },
    max_undo_history = 50,
    auto_backup_count = 5,
    auto_load_on_start = true,
    tempo_mode = "beat",
    track_position = "top",
    track_pinned = false,
    track_prefix = "IT: ",
    track_prefix_enabled = true,
    compact_mode = false,
    compact_offset_x = -40,
    compact_offset_y = 2,
    compact_icon_only = false,
    compact_no_bg = false,
    compact_icon_size = 28,
    compact_lock_position = false,
    compact_locked_x = nil,
    compact_locked_y = nil,
    preview_compact = true,
    show_settings = false,
    hide_window = false,
    settings_tab = "General"
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
    show_undo_list = false,
    show_backup_list = false,
    show_snapshot_list = false,
    show_snapshot_save = false,
    snapshot_name_input = "",
    close_action = nil,
    status_message = "",
    status_time = 0,
    settings_tab = 0,
    force_tab_select = false,
    settings_tab_initialized = false,
    compact_dragging = false,
    compact_drag_start_x = 0,
    compact_drag_start_y = 0,
    compact_drag_offset_x = 0,
    compact_drag_offset_y = 0
}

local profile_states = {}

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

local function JsonEncode(tbl, indent)
    indent = indent or 0
    local spaces = string.rep("  ", indent)
    local inner_spaces = string.rep("  ", indent + 1)
    
    local is_array = false
    local n = 0
    for k, _ in pairs(tbl) do
        n = n + 1
        if type(k) ~= "number" or k ~= n then
            is_array = false
            break
        end
        is_array = true
    end
    
    if is_array then
        local json = "[\n"
        local first = true
        for i, v in ipairs(tbl) do
            if not first then json = json .. ",\n" end
            first = false
            json = json .. inner_spaces
            if type(v) == "string" then
                v = v:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r')
                json = json .. '"' .. v .. '"'
            elseif type(v) == "number" then
                json = json .. tostring(v)
            elseif type(v) == "boolean" then
                json = json .. (v and "true" or "false")
            elseif type(v) == "table" then
                json = json .. JsonEncode(v, indent + 1)
            else
                json = json .. "null"
            end
        end
        return json .. "\n" .. spaces .. "]"
    else
        local json = "{\n"
        local first = true
        for k, v in pairs(tbl) do
            if not first then json = json .. ",\n" end
            first = false
            json = json .. inner_spaces .. '"' .. tostring(k) .. '": '
            if type(v) == "string" then
                v = v:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r')
                json = json .. '"' .. v .. '"'
            elseif type(v) == "number" then
                json = json .. tostring(v)
            elseif type(v) == "boolean" then
                json = json .. (v and "true" or "false")
            elseif type(v) == "table" then
                json = json .. JsonEncode(v, indent + 1)
            else
                json = json .. "null"
            end
        end
        return json .. "\n" .. spaces .. "}"
    end
end

local function JsonDecode(str)
    if not str or str == "" then return nil end
    
    local pos = 1
    local len = #str
    
    local function skip_whitespace()
        while pos <= len and str:sub(pos, pos):match("%s") do
            pos = pos + 1
        end
    end
    
    local function parse_string()
        if str:sub(pos, pos) ~= '"' then return nil end
        pos = pos + 1
        local start = pos
        local result = ""
        while pos <= len do
            local c = str:sub(pos, pos)
            if c == '\\' and pos < len then
                local nc = str:sub(pos + 1, pos + 1)
                if nc == 'n' then result = result .. "\n"
                elseif nc == 'r' then result = result .. "\r"
                elseif nc == 't' then result = result .. "\t"
                elseif nc == '"' then result = result .. '"'
                elseif nc == '\\' then result = result .. '\\'
                else result = result .. nc
                end
                pos = pos + 2
            elseif c == '"' then
                pos = pos + 1
                return result
            else
                result = result .. c
                pos = pos + 1
            end
        end
        return result
    end
    
    local parse_value
    
    local function parse_array()
        if str:sub(pos, pos) ~= '[' then return nil end
        pos = pos + 1
        local arr = {}
        skip_whitespace()
        if str:sub(pos, pos) == ']' then
            pos = pos + 1
            return arr
        end
        while pos <= len do
            skip_whitespace()
            local val = parse_value()
            table.insert(arr, val)
            skip_whitespace()
            local c = str:sub(pos, pos)
            if c == ']' then
                pos = pos + 1
                return arr
            elseif c == ',' then
                pos = pos + 1
            else
                break
            end
        end
        return arr
    end
    
    local function parse_object()
        if str:sub(pos, pos) ~= '{' then return nil end
        pos = pos + 1
        local obj = {}
        skip_whitespace()
        if str:sub(pos, pos) == '}' then
            pos = pos + 1
            return obj
        end
        while pos <= len do
            skip_whitespace()
            local key = parse_string()
            if not key then break end
            skip_whitespace()
            if str:sub(pos, pos) ~= ':' then break end
            pos = pos + 1
            skip_whitespace()
            local val = parse_value()
            obj[key] = val
            skip_whitespace()
            local c = str:sub(pos, pos)
            if c == '}' then
                pos = pos + 1
                return obj
            elseif c == ',' then
                pos = pos + 1
            else
                break
            end
        end
        return obj
    end
    
    parse_value = function()
        skip_whitespace()
        local c = str:sub(pos, pos)
        if c == '"' then
            return parse_string()
        elseif c == '{' then
            return parse_object()
        elseif c == '[' then
            return parse_array()
        elseif str:sub(pos, pos + 3) == "true" then
            pos = pos + 4
            return true
        elseif str:sub(pos, pos + 4) == "false" then
            pos = pos + 5
            return false
        elseif str:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            return nil
        else
            local num_str = str:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*", pos)
            if num_str then
                pos = pos + #num_str
                return tonumber(num_str)
            end
        end
        return nil
    end
    
    local success, result = pcall(function()
        skip_whitespace()
        return parse_value()
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
    for k, v in pairs(default_config) do
        if k == "profiles" then
            config.profiles = {}
            for i, p in ipairs(v) do
                config.profiles[i] = {}
                for pk, pv in pairs(p) do
                    config.profiles[i][pk] = pv
                end
            end
        else
            config[k] = v
        end
    end
    
    local f = io.open(CONFIG_FILE, "r")
    if f then
        local content = f:read("*all")
        f:close()
        local loaded = JsonDecode(content)
        if loaded then
            for k, v in pairs(loaded) do
                if k ~= "profiles" then
                    config[k] = v
                end
            end
            
            if loaded.profiles and type(loaded.profiles) == "table" then
                for i = 1, 4 do
                    if loaded.profiles[i] then
                        config.profiles[i].name = loaded.profiles[i].track_name or loaded.profiles[i].name or config.profiles[i].name
                        config.profiles[i].track_color = loaded.profiles[i].track_color or config.profiles[i].track_color
                        config.profiles[i].enabled = loaded.profiles[i].enabled
                        if config.profiles[i].enabled == nil then
                            config.profiles[i].enabled = (i == 1)
                        end
                    end
                end
            end
            
            if config.compact_offset_x and (config.compact_offset_x < -500 or config.compact_offset_x > 50) then
                config.compact_offset_x = -40
            end
            if config.compact_offset_y and (config.compact_offset_y < -50 or config.compact_offset_y > 200) then
                config.compact_offset_y = 2
            end
            
            return
        end
    end
end

local function GetActiveProfile()
    if not config.profiles or type(config.profiles) ~= "table" or #config.profiles == 0 then
        config.profiles = {{
            name = "Default",
            track_name = "Indestructible",
            track_color = 0x1E5A8A,
            data_file = "TK_IndestructibleTrack_data.json"
        }}
        config.active_profile = 1
    end
    local idx = config.active_profile or 1
    if idx < 1 or idx > #config.profiles then idx = 1 end
    config.active_profile = idx
    local profile = config.profiles[idx]
    if not profile then
        profile = {
            name = "Default",
            track_name = "Indestructible",
            track_color = 0x1E5A8A,
            data_file = "TK_IndestructibleTrack_data.json"
        }
        config.profiles[idx] = profile
    end
    return profile, idx
end

local function GetProfileTrackFile(profile)
    if not profile then profile = GetActiveProfile() end
    if not profile then
        return DATA_DIR .. "TK_IndestructibleTrack_data.json"
    end
    return DATA_DIR .. (profile.data_file or "TK_IndestructibleTrack_data.json")
end

local function GetProfileHistoryDir(profile)
    if not profile then profile = GetActiveProfile() end
    if not profile then return HISTORY_DIR .. "default/" end
    local safe_name = (profile.name or "default"):gsub("[^%w%-_]", "_"):lower()
    local dir = HISTORY_DIR .. safe_name .. "/"
    r.RecursiveCreateDirectory(dir, 0)
    return dir
end

local function GetProfilePExtKey(profile)
    if not profile then profile = GetActiveProfile() end
    if not profile then return "P_EXT:TK_IT_DEFAULT" end
    local idx = 1
    for i, p in ipairs(config.profiles) do
        if p == profile then
            idx = i
            break
        end
    end
    return "P_EXT:TK_IT_PROFILE_" .. idx
end

local function GetProfileStateKey(profile)
    if not profile then profile = GetActiveProfile() end
    if not profile then return "profile_1" end
    for i, p in ipairs(config.profiles) do
        if p == profile then
            return "profile_" .. i
        end
    end
    return "profile_1"
end

local function GetTrackPrefix()
    if config.track_prefix_enabled then
        return config.track_prefix or "IT: "
    end
    return ""
end

local function GetFullTrackName(profile)
    if not profile then profile = GetActiveProfile() end
    local prefix = GetTrackPrefix()
    if not profile then return prefix .. "Track" end
    return prefix .. (profile.name or "Track")
end
local function IsProfileEnabled(profile)
    return profile and profile.enabled == true
end

local function GetEnabledProfiles()
    local enabled = {}
    for _, profile in ipairs(config.profiles) do
        if IsProfileEnabled(profile) then
            table.insert(enabled, profile)
        end
    end
    return enabled
end

local RemoveTrackForProfile

local function GetOrCreateProfileState(profile)
    local key = GetProfileStateKey(profile)
    if not profile_states[key] then
        profile_states[key] = {
            track_ptr = nil,
            track_guid = nil,
            last_chunk = nil,
            last_normalized_chunk = nil,
            undo_history = {},
            undo_index = 0,
            cached_chunk_for_switch = nil,
            cached_normalized_for_switch = nil,
            last_file_timestamp = nil
        }
    end
    return profile_states[key]
end

local function FindTrackForProfile(profile)
    local track_count = r.CountTracks(0)
    if track_count == 0 then return nil end
    
    local pext_key = GetProfilePExtKey(profile)
    
    for i = 0, track_count - 1 do
        local track = r.GetTrack(0, i)
        local retval, marker = r.GetSetMediaTrackInfo_String(track, pext_key, "", false)
        if retval and marker == "1" then
            return track
        end
    end
    
    for i = 0, track_count - 1 do
        local track = r.GetTrack(0, i)
        local retval, name = r.GetTrackName(track)
        if name == GetFullTrackName(profile) or name == profile.name then
            r.GetSetMediaTrackInfo_String(track, pext_key, "1", true)
            r.GetSetMediaTrackInfo_String(track, "P_NAME", GetFullTrackName(profile), true)
            return track
        end
    end
    
    return nil
end

local function GetProfileTrackFileForProfile(profile)
    local filename = profile.data_file or "TK_IT_default_data.json"
    return DATA_DIR .. filename
end

local function GetSavedDataTimestamp()
    local track_file = GetProfileTrackFile()
    if not FileExists(track_file) then return nil end
    local f = io.open(track_file, "r")
    if not f then return nil end
    local content = f:read("*all")
    f:close()
    local timestamp = content:match('"timestamp":"([^"]+)"')
    return timestamp
end

local function SetStatus(msg, is_error)
    state.status_message = msg
    state.status_time = r.time_precise()
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
        r.SetMediaTrackInfo_Value(track, "C_TCPPIN", should_pin and 1 or 0)
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

local function SaveTrackDataForProfile(profile, track, chunk, tempo_override)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end
    if not chunk then
        chunk = GetTrackChunk(track)
    end
    if not chunk then return false end
    
    if not profile then profile = GetActiveProfile() end
    
    chunk = CopyMediaAndUpdateChunk(chunk)
    
    EnsureDirectories()
    
    local track_file = GetProfileTrackFile(profile)
    local history_dir = GetProfileHistoryDir(profile)
    
    local f = io.open(track_file, "r")
    if f then
        local old_content = f:read("*all")
        f:close()
        if old_content and old_content ~= "" then
            local backup_name = history_dir .. "backup_" .. os.date("%Y%m%d_%H%M%S") .. ".json"
            local bf = io.open(backup_name, "w")
            if bf then
                bf:write(old_content)
                bf:close()
            end
            CleanupOldBackups(profile)
        end
    end
    
    chunk = chunk:gsub("\n", "<<<NEWLINE>>>")
    
    local tempo = tempo_override or r.Master_GetTempo()
    
    local data = {
        version = SCRIPT_VERSION,
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        track_name = profile.name,
        profile_name = profile.name,
        tempo = tempo,
        chunk = chunk,
        media_items = GetMediaItemsData(track)
    }
    
    local f = io.open(track_file, "w")
    if f then
        f:write(JsonEncode(data))
        f:close()
        return true
    end
    return false
end

local function SaveTrackData()
    return SaveTrackDataForProfile(GetActiveProfile(), state.track_ptr, state.last_chunk)
end

function CleanupOldBackups(profile)
    local history_dir = GetProfileHistoryDir(profile)
    local files = {}
    local idx = 0
    
    while true do
        local filename = r.EnumerateFiles(history_dir, idx)
        if not filename then break end
        if filename:match("^backup_.*%.json$") then
            table.insert(files, filename)
        end
        idx = idx + 1
    end
    
    table.sort(files, function(a, b) return a > b end)
    
    while #files > config.auto_backup_count do
        local to_delete = table.remove(files)
        os.remove(history_dir .. to_delete)
    end
end

local function LoadTrackData()
    local track_file = GetProfileTrackFile()
    local f = io.open(track_file, "r")
    if not f then return nil end
    local content = f:read("*all")
    f:close()
    
    if not content or content == "" then return nil end
    
    local data = {}
    
    local chunk_start = content:find('"chunk":%s*"', 1)
    if chunk_start then
        chunk_start = content:find('"', chunk_start + 7, true)
        if chunk_start then
            chunk_start = chunk_start + 1
        
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
    end
    
    local name_match = content:match('"track_name":%s*"([^"]*)"')
    if name_match then
        data.track_name = name_match
    end
    
    local tempo_match = content:match('"tempo":%s*([%d%.]+)')
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

local function AddToUndoHistoryForProfile(profile, chunk)
    local pstate = GetOrCreateProfileState(profile)
    
    if pstate.undo_index < #pstate.undo_history then
        for i = #pstate.undo_history, pstate.undo_index + 1, -1 do
            table.remove(pstate.undo_history, i)
        end
    end
    
    local prev_chunk = pstate.undo_history[#pstate.undo_history] and pstate.undo_history[#pstate.undo_history].chunk or nil
    local desc = DetectChangeType(prev_chunk, chunk)
    
    table.insert(pstate.undo_history, {
        chunk = chunk,
        timestamp = os.date("%H:%M:%S"),
        description = desc
    })
    
    while #pstate.undo_history > config.max_undo_history do
        table.remove(pstate.undo_history, 1)
    end
    
    pstate.undo_index = #pstate.undo_history
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

local function UndoTrackForProfile(profile)
    local pstate = GetOrCreateProfileState(profile)
    
    if pstate.undo_index <= 1 then
        SetStatus("No earlier states for " .. profile.name)
        return false
    end
    
    pstate.undo_index = pstate.undo_index - 1
    local history_entry = pstate.undo_history[pstate.undo_index]
    
    if pstate.track_ptr and r.ValidatePtr(pstate.track_ptr, "MediaTrack*") then
        r.Undo_BeginBlock()
        r.PreventUIRefresh(1)
        SetTrackChunk(pstate.track_ptr, history_entry.chunk)
        pstate.last_chunk = history_entry.chunk
        pstate.last_normalized_chunk = NormalizeChunkForComparison(history_entry.chunk)
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock(profile.name .. " - Undo", -1)
        SetStatus(profile.name .. ": Undo " .. pstate.undo_index .. "/" .. #pstate.undo_history)
        return true
    end
    return false
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

local function RedoTrackForProfile(profile)
    local pstate = GetOrCreateProfileState(profile)
    
    if pstate.undo_index >= #pstate.undo_history then
        SetStatus("No later states for " .. profile.name)
        return false
    end
    
    pstate.undo_index = pstate.undo_index + 1
    local history_entry = pstate.undo_history[pstate.undo_index]
    
    if pstate.track_ptr and r.ValidatePtr(pstate.track_ptr, "MediaTrack*") then
        r.Undo_BeginBlock()
        r.PreventUIRefresh(1)
        SetTrackChunk(pstate.track_ptr, history_entry.chunk)
        pstate.last_chunk = history_entry.chunk
        pstate.last_normalized_chunk = NormalizeChunkForComparison(history_entry.chunk)
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock(profile.name .. " - Redo", -1)
        SetStatus(profile.name .. ": Redo " .. pstate.undo_index .. "/" .. #pstate.undo_history)
        return true
    end
    return false
end

local function JumpToHistoryForProfile(profile, target_index)
    local pstate = GetOrCreateProfileState(profile)
    
    if target_index < 1 or target_index > #pstate.undo_history then
        return false
    end
    if target_index == pstate.undo_index then
        return true
    end
    
    pstate.undo_index = target_index
    local history_entry = pstate.undo_history[pstate.undo_index]
    
    if pstate.track_ptr and r.ValidatePtr(pstate.track_ptr, "MediaTrack*") then
        r.Undo_BeginBlock()
        r.PreventUIRefresh(1)
        SetTrackChunk(pstate.track_ptr, history_entry.chunk)
        pstate.last_chunk = history_entry.chunk
        pstate.last_normalized_chunk = NormalizeChunkForComparison(history_entry.chunk)
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock(profile.name .. " - Jump to state", -1)
        SetStatus(profile.name .. ": Jump to " .. pstate.undo_index .. "/" .. #pstate.undo_history)
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
    local history_dir = GetProfileHistoryDir()
    local idx = 0
    while true do
        local filename = r.EnumerateFiles(history_dir, idx)
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
                    path = history_dir .. filename,
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
    
    local profile = GetActiveProfile()
    local pext_key = GetProfilePExtKey(profile)
    
    chunk = chunk:gsub('NAME ".-"', 'NAME "' .. GetFullTrackName(profile) .. '"', 1)
    
    if not state.track_ptr or not r.ValidatePtr(state.track_ptr, "MediaTrack*") then
        state.track_ptr = FindIndestructibleTrack()
        if not state.track_ptr then
            r.InsertTrackAtIndex(0, true)
            state.track_ptr = r.GetTrack(0, 0)
            r.GetSetMediaTrackInfo_String(state.track_ptr, "P_NAME", GetFullTrackName(profile), true)
            r.GetSetMediaTrackInfo_String(state.track_ptr, pext_key, "1", true)
            state.track_guid = r.GetTrackGUID(state.track_ptr)
        end
    end
    
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    SetTrackChunk(state.track_ptr, chunk)
    r.GetSetMediaTrackInfo_String(state.track_ptr, "P_NAME", GetFullTrackName(profile), true)
    r.GetSetMediaTrackInfo_String(state.track_ptr, pext_key, "1", true)
    state.last_chunk = chunk
    state.last_normalized_chunk = NormalizeChunkForComparison(chunk)
    AddToUndoHistory(chunk)
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("Load Indestructible Track Backup", -1)
    
    SaveTrackData()
    
    SetStatus("Backup loaded: " .. backup.display)
    return true
end

local function ScanBackupsForProfile(profile)
    if not profile then return {} end
    local backups = {}
    local history_dir = GetProfileHistoryDir(profile)
    local idx = 0
    while true do
        local filename = r.EnumerateFiles(history_dir, idx)
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
                table.insert(backups, {
                    filename = filename,
                    path = history_dir .. filename,
                    timestamp = display,
                    sort_key = timestamp
                })
            end
        end
        idx = idx + 1
    end
    table.sort(backups, function(a, b) return a.sort_key > b.sort_key end)
    return backups
end

local function LoadBackupForProfile(profile, backup)
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
        chunk_marker = '"chunk": "'
        chunk_start = content:find(chunk_marker, 1, true)
    end
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
            chunk_end = quote_pos - 1
            break
        end
        search_pos = quote_pos + 1
    end
    
    if not chunk_end then
        SetStatus("Could not parse backup", true)
        return false
    end
    
    local chunk = content:sub(chunk_start, chunk_end)
    chunk = chunk:gsub("<<<NEWLINE>>>", "\n")
    chunk = chunk:gsub('\\n', '\n')
    chunk = chunk:gsub('\\"', '"')
    chunk = chunk:gsub('\\\\', '\\')
    
    local pext_key = GetProfilePExtKey(profile)
    local profile_key = GetProfileStateKey(profile)
    local pstate = GetOrCreateProfileState(profile)
    
    chunk = chunk:gsub('NAME ".-"', 'NAME "' .. GetFullTrackName(profile) .. '"', 1)
    
    if not pstate.track_ptr or not r.ValidatePtr(pstate.track_ptr, "MediaTrack*") then
        pstate.track_ptr = FindTrackForProfile(profile)
        if not pstate.track_ptr then
            r.InsertTrackAtIndex(0, true)
            pstate.track_ptr = r.GetTrack(0, 0)
            r.GetSetMediaTrackInfo_String(pstate.track_ptr, "P_NAME", GetFullTrackName(profile), true)
            r.GetSetMediaTrackInfo_String(pstate.track_ptr, pext_key, "1", true)
            pstate.track_guid = r.GetTrackGUID(pstate.track_ptr)
        end
    end
    
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    SetTrackChunk(pstate.track_ptr, chunk)
    r.GetSetMediaTrackInfo_String(pstate.track_ptr, "P_NAME", GetFullTrackName(profile), true)
    r.GetSetMediaTrackInfo_String(pstate.track_ptr, pext_key, "1", true)
    pstate.last_chunk = chunk
    pstate.last_normalized_chunk = NormalizeChunkForComparison(chunk)
    AddToUndoHistoryForProfile(profile, chunk)
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("Load " .. profile.name .. " Backup", -1)
    
    SaveTrackDataForProfile(profile, pstate.track_ptr, chunk)
    
    SetStatus("Backup loaded: " .. backup.timestamp)
    return true
end

local function GetProfileSnapshotsDir(profile)
    if not profile then profile = GetActiveProfile() end
    local profile_key = GetProfileStateKey(profile)
    return DATA_DIR .. "snapshots/" .. profile_key .. "/"
end

local function ScanSnapshotsForProfile(profile)
    if not profile then return {} end
    local snapshots = {}
    local snapshots_dir = GetProfileSnapshotsDir(profile)
    r.RecursiveCreateDirectory(snapshots_dir, 0)
    local idx = 0
    while true do
        local filename = r.EnumerateFiles(snapshots_dir, idx)
        if not filename then break end
        if filename:match("%.json$") then
            local f = io.open(snapshots_dir .. filename, "r")
            if f then
                local content = f:read("*all")
                f:close()
                local name = content:match('"name":"([^"]*)"') or filename:gsub("%.json$", "")
                local timestamp = content:match('"timestamp":"([^"]*)"') or ""
                table.insert(snapshots, {
                    filename = filename,
                    path = snapshots_dir .. filename,
                    name = name,
                    timestamp = timestamp,
                    display = name .. " (" .. timestamp .. ")"
                })
            end
        end
        idx = idx + 1
    end
    table.sort(snapshots, function(a, b) return a.timestamp > b.timestamp end)
    return snapshots
end

local function ScanSnapshots()
    available_snapshots = ScanSnapshotsForProfile(GetActiveProfile())
end

local function SaveSnapshotForProfile(profile, name)
    if not profile then return false end
    local profile_key = GetProfileStateKey(profile)
    local pstate = profile_states[profile_key]
    
    if not pstate or not pstate.track_ptr or not r.ValidatePtr(pstate.track_ptr, "MediaTrack*") then
        SetStatus("No track to save", true)
        return false
    end
    
    local chunk = GetTrackChunk(pstate.track_ptr)
    if not chunk then
        SetStatus("Could not get track data", true)
        return false
    end
    
    local snapshots_dir = GetProfileSnapshotsDir(profile)
    r.RecursiveCreateDirectory(snapshots_dir, 0)
    
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
    
    local f = io.open(snapshots_dir .. filename, "w")
    if not f then
        SetStatus("Could not save snapshot", true)
        return false
    end
    f:write(json)
    f:close()
    
    SetStatus("Snapshot saved: " .. name)
    return true
end

local function SaveSnapshot(name)
    return SaveSnapshotForProfile(GetActiveProfile(), name)
end

local function LoadSnapshotForProfile(profile, snapshot)
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
    
    local pext_key = GetProfilePExtKey(profile)
    local profile_key = GetProfileStateKey(profile)
    local pstate = GetOrCreateProfileState(profile)
    
    chunk = chunk:gsub('NAME ".-"', 'NAME "' .. GetFullTrackName(profile) .. '"', 1)
    
    if not pstate.track_ptr or not r.ValidatePtr(pstate.track_ptr, "MediaTrack*") then
        pstate.track_ptr = FindTrackForProfile(profile)
        if not pstate.track_ptr then
            r.InsertTrackAtIndex(0, true)
            pstate.track_ptr = r.GetTrack(0, 0)
            r.GetSetMediaTrackInfo_String(pstate.track_ptr, "P_NAME", GetFullTrackName(profile), true)
            r.GetSetMediaTrackInfo_String(pstate.track_ptr, pext_key, "1", true)
            pstate.track_guid = r.GetTrackGUID(pstate.track_ptr)
        end
    end
    
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    SetTrackChunk(pstate.track_ptr, chunk)
    r.GetSetMediaTrackInfo_String(pstate.track_ptr, "P_NAME", GetFullTrackName(profile), true)
    r.GetSetMediaTrackInfo_String(pstate.track_ptr, pext_key, "1", true)
    pstate.last_chunk = chunk
    pstate.last_normalized_chunk = NormalizeChunkForComparison(chunk)
    AddToUndoHistoryForProfile(profile, chunk)
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("Load " .. profile.name .. " Snapshot", -1)
    
    SaveTrackDataForProfile(profile, pstate.track_ptr, chunk)
    
    SetStatus("Snapshot loaded: " .. snapshot.name)
    return true
end

local function LoadSnapshot(snapshot)
    return LoadSnapshotForProfile(GetActiveProfile(), snapshot)
end

local function DeleteSnapshotForProfile(profile, snapshot)
    os.remove(snapshot.path)
    SetStatus("Snapshot deleted: " .. snapshot.name)
end

local function DeleteSnapshot(snapshot)
    DeleteSnapshotForProfile(GetActiveProfile(), snapshot)
end

local function FindIndestructibleTrack()
    local track_count = r.CountTracks(0)
    local profile = GetActiveProfile()
    local pext_key = GetProfilePExtKey(profile)
    
    for i = 0, track_count - 1 do
        local track = r.GetTrack(0, i)
        local retval, marker = r.GetSetMediaTrackInfo_String(track, pext_key, "", false)
        if retval and marker == "1" then
            return track, r.BR_GetMediaItemGUID and r.GetTrackGUID(track) or nil
        end
    end
    
    for i = 0, track_count - 1 do
        local track = r.GetTrack(0, i)
        local retval, marker = r.GetSetMediaTrackInfo_String(track, "P_EXT:TK_INDESTRUCTIBLE", "", false)
        if retval and marker == "1" then
            r.GetSetMediaTrackInfo_String(track, pext_key, "1", true)
            return track, r.BR_GetMediaItemGUID and r.GetTrackGUID(track) or nil
        end
    end
    
    for i = 0, track_count - 1 do
        local track = r.GetTrack(0, i)
        local retval, name = r.GetTrackName(track)
        if name == GetFullTrackName(profile) or name == profile.name then
            r.GetSetMediaTrackInfo_String(track, pext_key, "1", true)
            r.GetSetMediaTrackInfo_String(track, "P_NAME", GetFullTrackName(profile), true)
            return track, r.BR_GetMediaItemGUID and r.GetTrackGUID(track) or nil
        end
    end
    return nil, nil
end

local function CountITTracksInAllProjects()
    local count = 0
    local projects = {}
    local profile = GetActiveProfile()
    local pext_key = GetProfilePExtKey(profile)
    local idx = 0
    while true do
        local proj = r.EnumProjects(idx)
        if not proj then break end
        local track_count = r.CountTracks(proj)
        for i = 0, track_count - 1 do
            local track = r.GetTrack(proj, i)
            local retval, marker = r.GetSetMediaTrackInfo_String(track, pext_key, "", false)
            if retval and marker == "1" then
                count = count + 1
                table.insert(projects, {proj = proj, track = track})
                break
            end
            local retval2, marker2 = r.GetSetMediaTrackInfo_String(track, "P_EXT:TK_INDESTRUCTIBLE", "", false)
            if retval2 and marker2 == "1" then
                count = count + 1
                table.insert(projects, {proj = proj, track = track})
                break
            end
            local retval3, name = r.GetTrackName(track)
            if name == GetFullTrackName(profile) or name == profile.name then
                count = count + 1
                table.insert(projects, {proj = proj, track = track})
                break
            end
        end
        idx = idx + 1
    end
    return count, projects
end

local function RemoveITTracksFromAllProjects()
    local current_proj = r.EnumProjects(-1)
    
    local idx = 0
    while true do
        local proj = r.EnumProjects(idx)
        if not proj then break end
        
        r.SelectProjectInstance(proj)
        
        local tracks_to_delete = {}
        local track_count = r.CountTracks(0)
        
        for i = 0, track_count - 1 do
            local track = r.GetTrack(0, i)
            if track then
                local should_delete = false
                
                for _, profile in ipairs(config.profiles) do
                    local pext_key = GetProfilePExtKey(profile)
                    local retval, marker = r.GetSetMediaTrackInfo_String(track, pext_key, "", false)
                    if retval and marker == "1" then
                        should_delete = true
                        break
                    end
                    
                    local retval3, name = r.GetTrackName(track)
                    if name == GetFullTrackName(profile) or name == profile.name then
                        should_delete = true
                        break
                    end
                end
                
                if not should_delete then
                    local retval2, marker2 = r.GetSetMediaTrackInfo_String(track, "P_EXT:TK_INDESTRUCTIBLE", "", false)
                    if retval2 and marker2 == "1" then
                        should_delete = true
                    end
                end
                
                if should_delete then
                    table.insert(tracks_to_delete, track)
                end
            end
        end
        
        for i = #tracks_to_delete, 1, -1 do
            if r.ValidatePtr(tracks_to_delete[i], "MediaTrack*") then
                r.DeleteTrack(tracks_to_delete[i])
            end
        end
        
        idx = idx + 1
    end
    
    for _, profile in ipairs(config.profiles) do
        local profile_key = GetProfileStateKey(profile)
        if profile_states[profile_key] then
            profile_states[profile_key].track_ptr = nil
            profile_states[profile_key].track_guid = nil
        end
    end
    
    state.track_ptr = nil
    state.track_guid = nil
    state.is_monitoring = false
    
    if current_proj then
        r.SelectProjectInstance(current_proj)
    end
end

local function CreateIndestructibleTrack()
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    
    local profile = GetActiveProfile()
    local pext_key = GetProfilePExtKey(profile)
    
    local track_count = r.CountTracks(0)
    local insert_index = 0
    if config.track_position == "bottom" then
        insert_index = track_count
    end
    
    r.InsertTrackAtIndex(insert_index, true)
    local track = r.GetTrack(0, insert_index)
    
    if track then
        r.GetSetMediaTrackInfo_String(track, "P_NAME", GetFullTrackName(profile), true)
        r.GetSetMediaTrackInfo_String(track, pext_key, "1", true)
        
        local color_rgb = profile.track_color or 0x1E5A8A
        local native_color = r.ImGui_ColorConvertNative(color_rgb)
        r.SetTrackColor(track, native_color | 0x1000000)
        
        local should_pin = GetProjectPinStatus(0)
        if should_pin then
            r.SetMediaTrackInfo_Value(track, "B_TCPPIN", 1)
            r.SetMediaTrackInfo_Value(track, "C_TCPPIN", 1)
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

local function CountDuplicateITTracks()
    local count = 0
    local tracks = {}
    local track_count = r.CountTracks(0)
    local profile = GetActiveProfile()
    local pext_key = GetProfilePExtKey(profile)
    
    for i = 0, track_count - 1 do
        local track = r.GetTrack(0, i)
        local retval, marker = r.GetSetMediaTrackInfo_String(track, pext_key, "", false)
        if retval and marker == "1" then
            count = count + 1
            table.insert(tracks, {track = track, index = i})
        end
    end
    
    if count <= 1 then
        for i = 0, track_count - 1 do
            local track = r.GetTrack(0, i)
            local already_counted = false
            for _, t in ipairs(tracks) do
                if t.track == track then already_counted = true break end
            end
            if not already_counted then
                local retval, name = r.GetTrackName(track)
                if name == GetFullTrackName(profile) or name == profile.name then
                    count = count + 1
                    table.insert(tracks, {track = track, index = i})
                end
            end
        end
    end
    
    return count, tracks
end

local function CleanupDuplicateITTracks()
    local count, tracks = CountDuplicateITTracks()
    if count <= 1 then return nil end
    
    local profile = GetActiveProfile()
    local pext_key = GetProfilePExtKey(profile)
    
    local answer = r.MB(
        string.format("Found %d '%s' tracks in this project!\n\n" ..
            "This can happen if the script was closed improperly.\n\n" ..
            "Keep the first one and remove the duplicates?",
            count, profile.name),
        SCRIPT_NAME .. " - Duplicate Tracks Found",
        4
    )
    
    if answer == 6 then
        r.Undo_BeginBlock()
        r.PreventUIRefresh(1)
        
        local keep_track = tracks[1].track
        r.GetSetMediaTrackInfo_String(keep_track, pext_key, "1", true)
        
        for i = #tracks, 2, -1 do
            if r.ValidatePtr(tracks[i].track, "MediaTrack*") then
                r.DeleteTrack(tracks[i].track)
            end
        end
        
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("Remove duplicate Indestructible Tracks", -1)
        r.TrackList_AdjustWindows(false)
        
        SetStatus(string.format("Removed %d duplicate track(s)", count - 1))
        return keep_track
    end
    
    return tracks[1].track
end

local LoadOrCreateTrackForProfile
local LoadOrCreateAllProfileTracks
local ToggleProfile

local function LoadOrCreateTrack()
    local duplicate_cleaned = CleanupDuplicateITTracks()
    if duplicate_cleaned then
        state.track_ptr = duplicate_cleaned
        state.track_guid = r.GetTrackGUID(duplicate_cleaned)
        state.last_chunk = GetTrackChunk(duplicate_cleaned)
        state.last_normalized_chunk = NormalizeChunkForComparison(state.last_chunk)
        state.is_monitoring = true
        if state.last_chunk then
            AddToUndoHistory(state.last_chunk)
        end
        return duplicate_cleaned
    end
    
    local existing_track = FindIndestructibleTrack()
    
    if existing_track then
        state.track_ptr = existing_track
        state.track_guid = r.GetTrackGUID(existing_track)
        state.last_chunk = GetTrackChunk(existing_track)
        state.last_normalized_chunk = NormalizeChunkForComparison(state.last_chunk)
        
        local track_file = GetProfileTrackFile()
        local tf = io.open(track_file, "r")
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
        state.is_monitoring = true
        SetStatus("Existing track found and monitored")
        return existing_track
    end
    
    local saved_data = LoadTrackData()
    if saved_data and saved_data.chunk and config.auto_load_on_start then
        local profile = GetActiveProfile()
        local track_file = GetProfileTrackFile(profile)
        
        r.Undo_BeginBlock()
        r.PreventUIRefresh(1)
        
        r.InsertTrackAtIndex(0, true)
        local track = r.GetTrack(0, 0)
        
        if track then
            local success = SetTrackChunk(track, saved_data.chunk)
            if success then
                r.GetSetMediaTrackInfo_String(track, "P_NAME", GetFullTrackName(profile), true)
                state.track_ptr = track
                state.track_guid = r.GetTrackGUID(track)
                state.last_chunk = saved_data.chunk
                state.last_normalized_chunk = NormalizeChunkForComparison(saved_data.chunk)
                state.is_monitoring = true
                
                local tf = io.open(track_file, "r")
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

local function CopyTrackToProject(profile)
    if not profile then profile = GetActiveProfile() end
    
    local profile_key = GetProfileStateKey(profile)
    local pstate = profile_states[profile_key]
    
    if not pstate or not pstate.track_ptr or not r.ValidatePtr(pstate.track_ptr, "MediaTrack*") then
        SetStatus("No track to copy", true)
        return false
    end
    
    local track_ptr = pstate.track_ptr
    
    local proj_path = GetProjectMediaPath()
    if not proj_path then
        r.ShowMessageBox("Please save the project first.\n\nThe track copy needs a project folder to store the media files.", SCRIPT_NAME, 0)
        return false
    end
    
    local chunk = GetTrackChunk(track_ptr)
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
    
    updated_chunk = updated_chunk:gsub('NAME%s+"' .. profile.name .. '"', 'NAME "' .. profile.name .. ' (Copy)"')
    
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
            r.GetSetMediaTrackInfo_String(new_track, "P_NAME", GetFullTrackName(profile) .. " (Copy)", true)
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
local last_project_ptr = nil
local pending_change_time = nil
local pending_change_chunk = nil
local DEBOUNCE_DELAY = 0.5

local pending_changes_per_profile = {}

local function GetOrCreatePendingState(profile_key)
    if not pending_changes_per_profile[profile_key] then
        pending_changes_per_profile[profile_key] = {
            pending_time = nil,
            pending_chunk = nil
        }
    end
    return pending_changes_per_profile[profile_key]
end

local function FlushPendingChange()
    if not pending_change_time then return end
    if not state.track_ptr or not r.ValidatePtr(state.track_ptr, "MediaTrack*") then
        pending_change_time = nil
        pending_change_chunk = nil
        return
    end
    
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
    end
    
    pending_change_time = nil
    pending_change_chunk = nil
end

local cached_chunk_for_switch = nil
local cached_normalized_for_switch = nil
local cached_project_ptr = nil
local cached_chunks_per_profile = {}

local function LoadTrackDataForProfile(profile)
    local track_file = GetProfileTrackFileForProfile(profile)
    if not FileExists(track_file) then return nil end
    
    local f = io.open(track_file, "r")
    if not f then return nil end
    local content = f:read("*all")
    f:close()
    
    if not content or content == "" then return nil end
    
    local data = {}
    
    local chunk_start = content:find('"chunk":%s*"', 1)
    if chunk_start then
        chunk_start = content:find('"', chunk_start + 7, true)
        if chunk_start then
            chunk_start = chunk_start + 1
        
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
    end
    
    local name_match = content:match('"track_name":%s*"([^"]*)"')
    if name_match then
        data.track_name = name_match
    end
    
    local tempo_match = content:match('"tempo":%s*([%d%.]+)')
    if tempo_match then
        data.tempo = tonumber(tempo_match)
    end
    
    data.version = content:match('"version"%s*:%s*"([^"]+)"')
    data.timestamp = content:match('"timestamp"%s*:%s*"([^"]+)"')
    data.profile_name = content:match('"profile_name"%s*:%s*"([^"]+)"')
    
    return data
end

local function GetInsertIndexForProfile(profile)
    local track_count = r.CountTracks(0)
    
    if config.track_position == "bottom" then
        return track_count
    end
    
    local profile_index = 1
    for i, p in ipairs(config.profiles) do
        if p.data_file == profile.data_file then
            profile_index = i
            break
        end
    end
    
    local it_tracks_before = 0
    for i = 0, track_count - 1 do
        local track = r.GetTrack(0, i)
        if track then
            for j, p in ipairs(config.profiles) do
                if j < profile_index and IsProfileEnabled(p) then
                    local pext_key = GetProfilePExtKey(p)
                    local _, val = r.GetSetMediaTrackInfo_String(track, pext_key, "", false)
                    if val == "1" then
                        it_tracks_before = it_tracks_before + 1
                        break
                    end
                end
            end
        end
    end
    
    return it_tracks_before
end

LoadOrCreateTrackForProfile = function(profile)
    local pext_key = GetProfilePExtKey(profile)
    local profile_key = GetProfileStateKey(profile)
    local pstate = GetOrCreateProfileState(profile)
    
    local existing_track = FindTrackForProfile(profile)
    if existing_track then
        local current_chunk = GetTrackChunk(existing_track)
        local current_normalized = NormalizeChunkForComparison(current_chunk)
        
        local saved_data = LoadTrackDataForProfile(profile)
        if saved_data and saved_data.chunk then
            local saved_normalized = NormalizeChunkForComparison(saved_data.chunk)
            
            if saved_normalized and current_normalized and saved_normalized ~= current_normalized then
                local saved_time = saved_data.timestamp or "unknown"
                local answer = r.MB(
                    profile.name .. ":\n\nThe saved version (" .. saved_time .. ") differs from the track in this project.\n\nLoad the saved version?\n\nYes = Load saved version\nNo = Keep project track (overwrites saved)",
                    SCRIPT_NAME .. " - Sync Conflict",
                    4
                )
                if answer == 6 then
                    local chunk_to_load = saved_data.chunk
                    local current_tempo = r.Master_GetTempo()
                    local saved_tempo = saved_data.tempo
                    if saved_tempo and math.abs(current_tempo - saved_tempo) > 0.01 then
                        if config.tempo_mode == "beat" then
                            chunk_to_load = AdjustChunkToTempo(saved_data.chunk, saved_tempo, current_tempo)
                        end
                    end
                    
                    r.PreventUIRefresh(1)
                    SetTrackChunk(existing_track, chunk_to_load)
                    r.GetSetMediaTrackInfo_String(existing_track, "P_NAME", GetFullTrackName(profile), true)
                    r.PreventUIRefresh(-1)
                    
                    current_chunk = GetTrackChunk(existing_track)
                    current_normalized = NormalizeChunkForComparison(current_chunk)
                else
                    SaveTrackDataForProfile(profile, existing_track, current_chunk)
                end
            end
        end
        
        pstate.track_ptr = existing_track
        pstate.track_guid = r.GetTrackGUID(existing_track)
        pstate.last_chunk = current_chunk
        pstate.last_normalized_chunk = current_normalized
        pstate.is_monitoring = true
        if pstate.last_chunk and #pstate.undo_history == 0 then
            AddToUndoHistoryForProfile(profile, pstate.last_chunk)
        end
        return existing_track
    end
    
    local saved_data = LoadTrackDataForProfile(profile)
    if saved_data and saved_data.chunk and config.auto_load_on_start then
        local chunk_to_load = saved_data.chunk
        
        local current_tempo = r.Master_GetTempo()
        local saved_tempo = saved_data.tempo
        if saved_tempo and math.abs(current_tempo - saved_tempo) > 0.01 then
            if config.tempo_mode == "beat" then
                chunk_to_load = AdjustChunkToTempo(saved_data.chunk, saved_tempo, current_tempo)
            end
        end
        
        r.Undo_BeginBlock()
        r.PreventUIRefresh(1)
        
        local insert_index = GetInsertIndexForProfile(profile)
        
        r.InsertTrackAtIndex(insert_index, true)
        local track = r.GetTrack(0, insert_index)
        
        if track then
            local success = SetTrackChunk(track, chunk_to_load)
            if success then
                r.GetSetMediaTrackInfo_String(track, "P_NAME", GetFullTrackName(profile), true)
                r.GetSetMediaTrackInfo_String(track, pext_key, "1", true)
                
                pstate.track_ptr = track
                pstate.track_guid = r.GetTrackGUID(track)
                pstate.last_chunk = GetTrackChunk(track)
                pstate.last_normalized_chunk = NormalizeChunkForComparison(pstate.last_chunk)
                pstate.is_monitoring = true
                AddToUndoHistoryForProfile(profile, pstate.last_chunk)
                
                r.PreventUIRefresh(-1)
                r.Undo_EndBlock("Load " .. profile.name .. " Track", -1)
                return track
            end
        end
        
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("Load " .. profile.name .. " Track", -1)
    end
    
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    
    local insert_index = GetInsertIndexForProfile(profile)
    
    r.InsertTrackAtIndex(insert_index, true)
    local track = r.GetTrack(0, insert_index)
    
    if track then
        r.GetSetMediaTrackInfo_String(track, "P_NAME", GetFullTrackName(profile), true)
        r.GetSetMediaTrackInfo_String(track, pext_key, "1", true)
        
        local color_rgb = profile.track_color or 0x1E5A8A
        local native_color = r.ImGui_ColorConvertNative(color_rgb)
        r.SetTrackColor(track, native_color | 0x1000000)
        
        local should_pin = GetProjectPinStatus(0)
        if should_pin then
            r.SetMediaTrackInfo_Value(track, "B_TCPPIN", 1)
            r.SetMediaTrackInfo_Value(track, "C_TCPPIN", 1)
        end
        
        pstate.track_ptr = track
        pstate.track_guid = r.GetTrackGUID(track)
        pstate.last_chunk = GetTrackChunk(track)
        pstate.last_normalized_chunk = NormalizeChunkForComparison(pstate.last_chunk)
        pstate.is_monitoring = true
        AddToUndoHistoryForProfile(profile, pstate.last_chunk)
    end
    
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("Create " .. profile.name .. " Track", -1)
    
    return track
end

LoadOrCreateAllProfileTracks = function()
    local created_any = false
    
    for _, profile in ipairs(config.profiles) do
        if IsProfileEnabled(profile) then
            local track = LoadOrCreateTrackForProfile(profile)
            if track then
                created_any = true
            end
        end
    end
    
    r.TrackList_AdjustWindows(false)
    
    return created_any
end

RemoveTrackForProfile = function(profile)
    local pext_key = GetProfilePExtKey(profile)
    local track_count = r.CountTracks(0)
    
    for i = track_count - 1, 0, -1 do
        local track = r.GetTrack(0, i)
        if track then
            local retval, marker = r.GetSetMediaTrackInfo_String(track, pext_key, "", false)
            local retval3, name = r.GetTrackName(track)
            
            if (retval and marker == "1") or name == GetFullTrackName(profile) or name == profile.name then
                r.DeleteTrack(track)
            end
        end
    end
    
    local profile_key = GetProfileStateKey(profile)
    if profile_states[profile_key] then
        profile_states[profile_key].track_ptr = nil
        profile_states[profile_key].track_guid = nil
    end
end

local function RefreshToggleToolbar(profile_index, enabled)
    local cmd_str = r.GetExtState("TK_IndestructibleTrack", "cmd_profile_" .. profile_index)
    if cmd_str ~= "" then
        local cmd_id = tonumber(cmd_str)
        if cmd_id and cmd_id ~= 0 then
            r.SetToggleCommandState(0, cmd_id, enabled and 1 or 0)
            r.RefreshToolbar2(0, cmd_id)
        end
    end
end

ToggleProfile = function(profile_index, enabled)
    if profile_index < 1 or profile_index > 4 then return end
    
    local profile = config.profiles[profile_index]
    if not profile then return end
    
    local was_enabled = profile.enabled
    profile.enabled = enabled
    
    if enabled and not was_enabled then
        LoadOrCreateTrackForProfile(profile)
        r.TrackList_AdjustWindows(false)
    elseif not enabled and was_enabled then
        RemoveTrackForProfile(profile)
        r.TrackList_AdjustWindows(false)
    end
    
    r.SetExtState("TK_IndestructibleTrack", "state_profile_" .. profile_index, enabled and "1" or "0", false)
    RefreshToggleToolbar(profile_index, enabled)
    SaveConfig()
end

local function CheckInitialConflictForProfile(profile)
    local track = FindTrackForProfile(profile)
    if not track then return nil end
    
    local saved_data = LoadTrackDataForProfile(profile)
    if not saved_data or not saved_data.chunk then return track end
    
    local current_chunk = GetTrackChunk(track)
    if not current_chunk then return track end
    
    local current_normalized = NormalizeChunkForComparison(current_chunk)
    local saved_normalized = NormalizeChunkForComparison(saved_data.chunk)
    
    if current_normalized ~= saved_normalized then
        local saved_time = saved_data.timestamp or "unknown"
        local answer = r.MB(
            profile.name .. ":\n\nThe saved version (" .. saved_time .. ") differs from the track in this project.\n\nLoad the saved version?\n\nYes = Load saved version\nNo = Keep project track (overwrites saved)",
            SCRIPT_NAME .. " - Sync Conflict",
            4
        )
        
        if answer == 6 then
            local chunk_to_load = saved_data.chunk
            
            local current_tempo = r.Master_GetTempo()
            local saved_tempo = saved_data.tempo
            if saved_tempo and math.abs(current_tempo - saved_tempo) > 0.01 then
                if config.tempo_mode == "beat" then
                    chunk_to_load = AdjustChunkToTempo(saved_data.chunk, saved_tempo, current_tempo)
                end
            end
            
            r.PreventUIRefresh(1)
            SetTrackChunk(track, chunk_to_load)
            r.GetSetMediaTrackInfo_String(track, "P_NAME", GetFullTrackName(profile), true)
            local pext_key = GetProfilePExtKey(profile)
            r.GetSetMediaTrackInfo_String(track, pext_key, "1", true)
            r.PreventUIRefresh(-1)
        else
            SaveTrackDataForProfile(profile, track, current_chunk)
        end
    end
    
    return track
end

local function SyncProfileOnProjectSwitch(profile)
    local profile_key = GetProfileStateKey(profile)
    local pstate = GetOrCreateProfileState(profile)
    
    local cached = cached_chunks_per_profile[profile_key]
    if cached and cached.chunk then
        local saved_data = LoadTrackDataForProfile(profile)
        local needs_save = true
        if saved_data and saved_data.chunk then
            local saved_normalized = NormalizeChunkForComparison(saved_data.chunk)
            needs_save = cached.normalized ~= saved_normalized
        end
        if needs_save then
            pstate.last_chunk = cached.chunk
            pstate.last_normalized_chunk = cached.normalized
            pstate.last_file_timestamp = os.date("%Y-%m-%d %H:%M:%S")
            
            local track = FindTrackForProfile(profile)
            if track then
                SaveTrackDataForProfile(profile, track, cached.chunk, cached.tempo)
            end
        end
    end
    
    cached_chunks_per_profile[profile_key] = nil
    
    local track = FindTrackForProfile(profile)
    if track then
        pstate.track_ptr = track
        pstate.track_guid = r.GetTrackGUID(track)
        
        local saved_data = LoadTrackDataForProfile(profile)
        if saved_data and saved_data.chunk then
            local current_chunk = GetTrackChunk(track)
            if current_chunk then
                local current_normalized = NormalizeChunkForComparison(current_chunk)
                local saved_normalized = NormalizeChunkForComparison(saved_data.chunk)
                
                if current_normalized ~= saved_normalized then
                    local chunk_to_load = saved_data.chunk
                    
                    local current_tempo = r.Master_GetTempo()
                    local saved_tempo = saved_data.tempo
                    if saved_tempo and math.abs(current_tempo - saved_tempo) > 0.01 then
                        if config.tempo_mode == "beat" then
                            chunk_to_load = AdjustChunkToTempo(saved_data.chunk, saved_tempo, current_tempo)
                        end
                    end
                    
                    r.Undo_BeginBlock()
                    r.PreventUIRefresh(1)
                    SetTrackChunk(track, chunk_to_load)
                    
                    r.GetSetMediaTrackInfo_String(track, "P_NAME", GetFullTrackName(profile), true)
                    local pext_key = GetProfilePExtKey(profile)
                    r.GetSetMediaTrackInfo_String(track, pext_key, "1", true)
                    
                    pstate.last_chunk = GetTrackChunk(track)
                    pstate.last_normalized_chunk = NormalizeChunkForComparison(pstate.last_chunk)
                    r.PreventUIRefresh(-1)
                    r.Undo_EndBlock("Sync " .. profile.name, -1)
                else
                    pstate.last_chunk = current_chunk
                    pstate.last_normalized_chunk = current_normalized
                end
            end
        end
        
        if profile == GetActiveProfile() then
            state.track_ptr = track
            state.track_guid = pstate.track_guid
            state.last_chunk = pstate.last_chunk
            state.last_normalized_chunk = pstate.last_normalized_chunk
            state.is_monitoring = true
        end
    else
        pstate.track_ptr = nil
        pstate.track_guid = nil
        if profile == GetActiveProfile() then
            state.track_ptr = nil
            state.is_monitoring = false
        end
    end
end

local function SyncAllProfilesOnProjectSwitch()
    for _, profile in ipairs(config.profiles) do
        if IsProfileEnabled(profile) then
            local track = FindTrackForProfile(profile)
            if track then
                SyncProfileOnProjectSwitch(profile)
            else
                LoadOrCreateTrackForProfile(profile)
            end
        else
            local track = FindTrackForProfile(profile)
            if track then
                r.Undo_BeginBlock()
                r.PreventUIRefresh(1)
                RemoveTrackForProfile(profile)
                r.PreventUIRefresh(-1)
                r.Undo_EndBlock("Remove disabled " .. profile.name, -1)
            end
        end
    end
    
    r.TrackList_AdjustWindows(false)
    
    for key, _ in pairs(pending_changes_per_profile) do
        pending_changes_per_profile[key] = nil
    end
    
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
end

local function UpdateCachedChunk()
    local current_project = r.EnumProjects(-1)
    if current_project ~= cached_project_ptr then
        return
    end
    
    local current_tempo = r.Master_GetTempo()
    
    for _, profile in ipairs(config.profiles) do
        if IsProfileEnabled(profile) then
            local profile_key = GetProfileStateKey(profile)
            local pstate = profile_states[profile_key]
            if pstate and pstate.track_ptr and r.ValidatePtr(pstate.track_ptr, "MediaTrack*") then
                local chunk = GetTrackChunk(pstate.track_ptr)
                if chunk then
                    cached_chunks_per_profile[profile_key] = {
                        chunk = chunk,
                        normalized = NormalizeChunkForComparison(chunk),
                        tempo = current_tempo
                    }
                end
            end
        end
    end
    
    if state.track_ptr and r.ValidatePtr(state.track_ptr, "MediaTrack*") then
        local chunk = GetTrackChunk(state.track_ptr)
        if chunk then
            cached_chunk_for_switch = chunk
            cached_normalized_for_switch = NormalizeChunkForComparison(chunk)
        end
    end
end

local function CheckForExternalChanges()
    local current_project = r.EnumProjects(-1)
    local project_changed = current_project ~= last_project_ptr
    
    if project_changed then
        last_project_ptr = current_project
        cached_project_ptr = current_project
        state.declined_create = nil
        
        SyncAllProfilesOnProjectSwitch()
        
        cached_chunk_for_switch = nil
        cached_normalized_for_switch = nil
        pending_change_time = nil
        pending_change_chunk = nil
        return
    end
end

local function ProcessPendingChange()
    if not pending_change_time then return end
    
    local now = r.time_precise()
    if now - pending_change_time < DEBOUNCE_DELAY then return end
    
    FlushPendingChange()
end

local function FlushPendingChangeForProfile(profile)
    local profile_key = GetProfileStateKey(profile)
    local pending = pending_changes_per_profile[profile_key]
    if not pending or not pending.pending_time then return end
    
    local pstate = GetOrCreateProfileState(profile)
    if not pstate.track_ptr or not r.ValidatePtr(pstate.track_ptr, "MediaTrack*") then
        pending.pending_time = nil
        pending.pending_chunk = nil
        return
    end
    
    local current_chunk = GetTrackChunk(pstate.track_ptr)
    if not current_chunk then
        pending.pending_time = nil
        pending.pending_chunk = nil
        return
    end
    
    local normalized_current = NormalizeChunkForComparison(current_chunk)
    
    AddToUndoHistoryForProfile(profile, current_chunk)
    
    pstate.last_chunk = current_chunk
    pstate.last_normalized_chunk = normalized_current
    pstate.last_file_timestamp = os.date("%Y-%m-%d %H:%M:%S")
    
    if SaveTrackDataForProfile(profile, pstate.track_ptr, current_chunk) then
        if profile == GetActiveProfile() then
            SetStatus("Auto-save: " .. profile.name .. " saved (" .. os.date("%H:%M:%S") .. ")")
        end
    end
    
    pending.pending_time = nil
    pending.pending_chunk = nil
end

local function ProcessPendingChangesAllProfiles()
    local now = r.time_precise()
    for _, profile in ipairs(config.profiles) do
        local profile_key = GetProfileStateKey(profile)
        local pending = pending_changes_per_profile[profile_key]
        if pending and pending.pending_time then
            if now - pending.pending_time >= DEBOUNCE_DELAY then
                FlushPendingChangeForProfile(profile)
            end
        end
    end
end

local function CheckForChangesForProfile(profile)
    local profile_key = GetProfileStateKey(profile)
    local pstate = GetOrCreateProfileState(profile)
    local pending = GetOrCreatePendingState(profile_key)
    
    if not pstate.track_ptr or not r.ValidatePtr(pstate.track_ptr, "MediaTrack*") then
        local track = FindTrackForProfile(profile)
        if track then
            pstate.track_ptr = track
            pstate.track_guid = r.GetTrackGUID(track)
            pstate.last_chunk = GetTrackChunk(track)
            pstate.last_normalized_chunk = NormalizeChunkForComparison(pstate.last_chunk)
            
            if profile == GetActiveProfile() then
                state.track_ptr = track
                state.track_guid = pstate.track_guid
                state.last_chunk = pstate.last_chunk
                state.last_normalized_chunk = pstate.last_normalized_chunk
                state.is_monitoring = true
            end
        else
            return
        end
    end
    
    local current_chunk = GetTrackChunk(pstate.track_ptr)
    if not current_chunk then return end
    
    local normalized_current = NormalizeChunkForComparison(current_chunk)
    
    if not pstate.last_normalized_chunk then
        pstate.last_normalized_chunk = normalized_current
        pstate.last_chunk = current_chunk
        return
    end
    
    if normalized_current ~= pstate.last_normalized_chunk then
        pending.pending_time = r.time_precise()
        pending.pending_chunk = current_chunk
        pstate.last_chunk = current_chunk
        pstate.last_normalized_chunk = normalized_current
        
        if profile == GetActiveProfile() then
            cached_chunk_for_switch = current_chunk
            cached_normalized_for_switch = normalized_current
        end
    end
end

local function CheckAllProfilesForChanges()
    for _, profile in ipairs(config.profiles) do
        if IsProfileEnabled(profile) then
            CheckForChangesForProfile(profile)
        end
    end
    ProcessPendingChangesAllProfiles()
end

local function CheckExternalToggleRequests()
    for i = 1, 4 do
        local toggle_val = r.GetExtState("TK_IndestructibleTrack", "toggle_profile_" .. i)
        if toggle_val ~= "" then
            r.DeleteExtState("TK_IndestructibleTrack", "toggle_profile_" .. i, false)
            if config.profiles and config.profiles[i] then
                local new_state = not config.profiles[i].enabled
                ToggleProfile(i, new_state)
                r.SetExtState("TK_IndestructibleTrack", "state_profile_" .. i, new_state and "1" or "0", false)
            end
        end
    end
end

local function CheckForChanges()
    CheckForExternalChanges()
    ProcessPendingChange()
    
    if not state.track_ptr or not r.ValidatePtr(state.track_ptr, "MediaTrack*") then
        local found_track = FindIndestructibleTrack()
        if found_track then
            state.track_ptr = found_track
            state.track_guid = r.GetTrackGUID(found_track)
            state.last_chunk = GetTrackChunk(found_track)
            state.last_normalized_chunk = NormalizeChunkForComparison(state.last_chunk)
            state.is_monitoring = true
            SetStatus("Track found in project")
        else
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
        cached_chunk_for_switch = current_chunk
        cached_normalized_for_switch = normalized_current
        return
    end
    
    if normalized_current ~= state.last_normalized_chunk then
        pending_change_time = r.time_precise()
        pending_change_chunk = current_chunk
        state.last_chunk = current_chunk
        state.last_normalized_chunk = normalized_current
        cached_chunk_for_switch = current_chunk
        cached_normalized_for_switch = normalized_current
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
    
    local _, main_left, main_top, _, _ = r.JS_Window_GetRect(main_hwnd)
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
        tcp_w = conv_tcp_total,
        tcp_left = conv_main_x
    }
end

local compact_font = nil
local compact_menu_font = nil
local compact_shield_image = nil
local compact_ctx = nil
local compact_popup_profile = nil
local settings_shield_image = nil
local settings_header_font = nil

local function DrawSingleCompactIcon(profile, pstate, widget_index)
    if not pstate or not pstate.track_ptr or not r.ValidatePtr(pstate.track_ptr, "MediaTrack*") then
        return
    end
    
    local icon_size = config.compact_icon_size or 28
    local font_size = math.max(10, math.floor(icon_size * 0.6))
    local padding_x = math.max(2, math.floor(icon_size * 0.2))
    local padding_y = math.max(1, math.floor(icon_size * 0.05))
    local rounding = math.max(2, math.floor(icon_size * 0.15))
    
    local bounds = GetTrackTCPBounds(pstate.track_ptr, compact_ctx)
    if not bounds then return end
    
    local widget_x, widget_y
    
    if config.compact_lock_position and config.compact_locked_x then
        widget_x = config.compact_locked_x
        widget_y = bounds.y + (config.compact_locked_y or 0)
    else
        widget_x = bounds.x + (config.compact_offset_x or -40)
        widget_y = bounds.y + (config.compact_offset_y or 2)
    end
    
    local window_name = "##compact_widget_" .. (profile.name or tostring(widget_index))
    
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
    
    local visible = r.ImGui_Begin(compact_ctx, window_name, true, flags)
    
    if visible then
        if compact_shield_image then
            r.ImGui_Image(compact_ctx, compact_shield_image, icon_size, icon_size)
        end
        
        if r.ImGui_IsWindowHovered(compact_ctx) and r.ImGui_IsMouseClicked(compact_ctx, 1) then
            r.ImGui_OpenPopup(compact_ctx, "compact_menu_" .. profile.name)
        end
        
        if r.ImGui_BeginPopup(compact_ctx, "compact_menu_" .. profile.name) then
            local profile_key = GetProfileStateKey(profile)
            local pstate = profile_states[profile_key] or {undo_history = {}, undo_index = 0}
            
            r.ImGui_PushFont(compact_ctx, compact_menu_font, 13)
            
            r.ImGui_TextColored(compact_ctx, 0xAAAAAAFF, profile.name)
            r.ImGui_Separator(compact_ctx)
            
            local can_undo = pstate.undo_index > 1
            local can_redo = pstate.undo_index < #pstate.undo_history
            local btn_w = 60
            
            r.ImGui_PushStyleColor(compact_ctx, r.ImGui_Col_Button(), 0x404040FF)
            r.ImGui_PushStyleColor(compact_ctx, r.ImGui_Col_ButtonHovered(), 0x505050FF)
            r.ImGui_PushStyleColor(compact_ctx, r.ImGui_Col_ButtonActive(), 0x606060FF)
            
            if not can_undo then
                r.ImGui_PushStyleVar(compact_ctx, r.ImGui_StyleVar_Alpha(), 0.4)
            end
            if r.ImGui_Button(compact_ctx, "< Undo", btn_w, 0) and can_undo then
                UndoTrackForProfile(profile)
            end
            if not can_undo then
                r.ImGui_PopStyleVar(compact_ctx)
            end
            
            r.ImGui_SameLine(compact_ctx)
            
            if not can_redo then
                r.ImGui_PushStyleVar(compact_ctx, r.ImGui_StyleVar_Alpha(), 0.4)
            end
            if r.ImGui_Button(compact_ctx, "Redo >", btn_w, 0) and can_redo then
                RedoTrackForProfile(profile)
            end
            if not can_redo then
                r.ImGui_PopStyleVar(compact_ctx)
            end
            
            r.ImGui_PopStyleColor(compact_ctx, 3)
            
            r.ImGui_Separator(compact_ctx)
            
            if r.ImGui_MenuItem(compact_ctx, "Save Now") then
                if pstate and pstate.track_ptr then
                    SaveTrackDataForProfile(profile, pstate.track_ptr, pstate.last_chunk)
                    SetStatus("Saved " .. profile.name)
                end
            end
            
            if r.ImGui_MenuItem(compact_ctx, "Save Snapshot") then
                local snap_name = profile.name .. " " .. os.date("%H:%M:%S")
                if SaveSnapshotForProfile(profile, snap_name) then
                    SetStatus("Snapshot saved: " .. snap_name)
                end
            end
            
            if r.ImGui_MenuItem(compact_ctx, "Copy to Project") then
                CopyTrackToProject(profile)
            end
            
            local items_locked = false
            if pstate and pstate.track_ptr and r.ValidatePtr(pstate.track_ptr, "MediaTrack*") then
                local item_count = r.CountTrackMediaItems(pstate.track_ptr)
                if item_count > 0 then
                    local first_item = r.GetTrackMediaItem(pstate.track_ptr, 0)
                    if first_item then
                        items_locked = r.GetMediaItemInfo_Value(first_item, "C_LOCK") == 1
                    end
                end
            end
            local lock_items_label = items_locked and "Unlock Items" or "Lock Items"
            if r.ImGui_MenuItem(compact_ctx, lock_items_label) then
                if pstate and pstate.track_ptr and r.ValidatePtr(pstate.track_ptr, "MediaTrack*") then
                    r.SetOnlyTrackSelected(pstate.track_ptr)
                    r.Main_OnCommand(40289, 0)
                    r.Main_OnCommand(43696, 0)
                end
            end
            
            local lock_label = config.compact_lock_position and "Unlock Position" or "Lock Position"
            if r.ImGui_MenuItem(compact_ctx, lock_label) then
                config.compact_lock_position = not config.compact_lock_position
                if config.compact_lock_position then
                    local bounds = GetTrackTCPBounds(pstate.track_ptr, compact_ctx)
                    if bounds then
                        config.compact_locked_x = bounds.x + (config.compact_offset_x or -40)
                        config.compact_locked_y = config.compact_offset_y or 2
                    end
                end
                SaveConfig()
            end
            
            if r.ImGui_MenuItem(compact_ctx, "Show Settings") then
                config.hide_window = false
                SaveConfig()
            end
            
            r.ImGui_Separator(compact_ctx)
            
            r.ImGui_PushStyleColor(compact_ctx, r.ImGui_Col_Text(), 0xCC6666FF)
            if r.ImGui_MenuItem(compact_ctx, "Close Script") then
                state.close_action = "exit"
            end
            r.ImGui_PopStyleColor(compact_ctx)
            
            r.ImGui_PopFont(compact_ctx)
            r.ImGui_EndPopup(compact_ctx)
        end
        
        if r.ImGui_IsWindowHovered(compact_ctx) and r.ImGui_IsMouseDoubleClicked(compact_ctx, 0) then
            config.compact_mode = false
            config.hide_window = false
            SaveConfig()
        end
        
        if not config.compact_lock_position then
            if r.ImGui_IsWindowHovered(compact_ctx) and r.ImGui_IsMouseClicked(compact_ctx, 0) then
                state.compact_dragging = true
                state.compact_drag_profile = profile.name
                local mouse_x, mouse_y = r.ImGui_GetMousePos(compact_ctx)
                state.compact_drag_start_x = mouse_x
                state.compact_drag_start_y = mouse_y
                state.compact_drag_offset_x = config.compact_offset_x or -40
                state.compact_drag_offset_y = config.compact_offset_y or 2
            end
        end
        
        if state.compact_dragging and state.compact_drag_profile == profile.name then
            if r.ImGui_IsMouseDown(compact_ctx, 0) then
                local mouse_x, mouse_y = r.ImGui_GetMousePos(compact_ctx)
                local delta_x = mouse_x - state.compact_drag_start_x
                local delta_y = mouse_y - state.compact_drag_start_y
                config.compact_offset_x = state.compact_drag_offset_x + delta_x
                config.compact_offset_y = state.compact_drag_offset_y + delta_y
            else
                state.compact_dragging = false
                state.compact_drag_profile = nil
                SaveConfig()
            end
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
end

local function DrawCompactWidget()
    local any_track_found = false
    local any_enabled = false
    
    for _, profile in ipairs(config.profiles) do
        if IsProfileEnabled(profile) then
            any_enabled = true
            local profile_key = GetProfileStateKey(profile)
            local pstate = profile_states[profile_key]
            if pstate and pstate.track_ptr and r.ValidatePtr(pstate.track_ptr, "MediaTrack*") then
                any_track_found = true
                break
            end
        end
    end
    
    if not any_enabled then
        return true
    end
    
    if not any_track_found then
        local found_track = FindIndestructibleTrack()
        if found_track then
            state.track_ptr = found_track
            state.track_guid = r.GetTrackGUID(found_track)
            state.last_chunk = GetTrackChunk(found_track)
            state.last_normalized_chunk = NormalizeChunkForComparison(state.last_chunk)
            state.is_monitoring = true
            state.declined_create = nil
            any_track_found = true
        else
            state.track_ptr = nil
            state.track_guid = nil
            state.is_monitoring = false
            
            if state.declined_create then
                return true
            end
            
            if not compact_ctx or not r.ImGui_ValidatePtr(compact_ctx, "ImGui_Context*") then
                compact_ctx = r.ImGui_CreateContext("TK_IT_Compact_Add")
            end
            
            local win_w, win_h = 280, 80
            local first_track = r.GetTrack(0, 0)
            local pos_x, pos_y
            if first_track then
                local bounds = GetTrackTCPBounds(first_track)
                pos_x = bounds and (bounds.x + config.compact_offset_x) or 100
                pos_y = bounds and (bounds.y + config.compact_offset_y) or 100
            else
                local mx, my = r.GetMousePosition()
                pos_x = mx - win_w / 2
                pos_y = my - win_h / 2
            end
            
            r.ImGui_SetNextWindowPos(compact_ctx, pos_x, pos_y, r.ImGui_Cond_Once())
            r.ImGui_SetNextWindowSize(compact_ctx, win_w, win_h, r.ImGui_Cond_Always())
            
            r.ImGui_PushStyleColor(compact_ctx, r.ImGui_Col_WindowBg(), 0x1E1E1EFF)
            r.ImGui_PushStyleColor(compact_ctx, r.ImGui_Col_Border(), 0x4A8A5AFF)
            r.ImGui_PushStyleColor(compact_ctx, r.ImGui_Col_Button(), 0x2A5A3AFF)
            r.ImGui_PushStyleColor(compact_ctx, r.ImGui_Col_ButtonHovered(), 0x3A7A4AFF)
            r.ImGui_PushStyleColor(compact_ctx, r.ImGui_Col_ButtonActive(), 0x4A9A5AFF)
            r.ImGui_PushStyleVar(compact_ctx, r.ImGui_StyleVar_WindowRounding(), 6)
            r.ImGui_PushStyleVar(compact_ctx, r.ImGui_StyleVar_WindowPadding(), 12, 10)
            r.ImGui_PushStyleVar(compact_ctx, r.ImGui_StyleVar_WindowBorderSize(), 1)
            r.ImGui_PushStyleVar(compact_ctx, r.ImGui_StyleVar_FrameRounding(), 4)
            
            local flags = r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_NoResize() | 
                          r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoMove()
            
            local visible = r.ImGui_Begin(compact_ctx, "IT_Create###it_create", true, flags)
            if visible then
                r.ImGui_TextColored(compact_ctx, 0xAAAAAAFF, "Create Indestructible Tracks in this project?")
                
                r.ImGui_Spacing(compact_ctx)
                r.ImGui_Separator(compact_ctx)
                r.ImGui_Spacing(compact_ctx)
                
                local btn_w = 80
                local spacing = 10
                local total_w = btn_w * 2 + spacing
                local avail_w = r.ImGui_GetContentRegionAvail(compact_ctx)
                r.ImGui_SetCursorPosX(compact_ctx, (avail_w - total_w) / 2)
                
                if r.ImGui_Button(compact_ctx, "Yes", btn_w, 24) then
                    LoadOrCreateAllProfileTracks()
                end
                
                r.ImGui_SameLine(compact_ctx)
                
                r.ImGui_PushStyleColor(compact_ctx, r.ImGui_Col_Button(), 0x5A2A2AFF)
                r.ImGui_PushStyleColor(compact_ctx, r.ImGui_Col_ButtonHovered(), 0x7A3A3AFF)
                r.ImGui_PushStyleColor(compact_ctx, r.ImGui_Col_ButtonActive(), 0x9A4A4AFF)
                if r.ImGui_Button(compact_ctx, "No", btn_w, 24) then
                    state.declined_create = true
                end
                r.ImGui_PopStyleColor(compact_ctx, 3)
                
                r.ImGui_End(compact_ctx)
            end
            
            r.ImGui_PopStyleVar(compact_ctx, 4)
            r.ImGui_PopStyleColor(compact_ctx, 5)
            
            return true
        end
    end
    
    if state.declined_create then
        state.declined_create = nil
    end
    
    local icon_size = config.compact_icon_size or 28
    local font_size = math.max(10, math.floor(icon_size * 0.6))
    local menu_font_size = 13
    
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
    
    local widget_index = 0
    
    for _, profile in ipairs(config.profiles) do
        if IsProfileEnabled(profile) then
            local profile_key = GetProfileStateKey(profile)
            local pstate = profile_states[profile_key]
            if pstate and pstate.track_ptr and r.ValidatePtr(pstate.track_ptr, "MediaTrack*") then
                DrawSingleCompactIcon(profile, pstate, widget_index)
                widget_index = widget_index + 1
            end
        end
    end
    
    return true
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

local function DrawCloseButton()
    local window_width = r.ImGui_GetWindowWidth(ctx)
    local close_size = 12
    local saved_cursor_y = r.ImGui_GetCursorPosY(ctx)
    r.ImGui_SetCursorPos(ctx, window_width - close_size - 10, 8)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xCC4444FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xDD5555FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xBB3333FF)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), close_size / 2)
    if r.ImGui_Button(ctx, "##close_script", close_size, close_size) then
        state.close_action = "exit"
    end
    r.ImGui_PopStyleVar(ctx)
    r.ImGui_PopStyleColor(ctx, 3)
    r.ImGui_SetCursorPosY(ctx, saved_cursor_y)
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
    DrawCloseButton()
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
    
    if #config.profiles > 1 then
        local profile, idx = GetActiveProfile()
        r.ImGui_SetNextItemWidth(ctx, -1)
        if r.ImGui_BeginCombo(ctx, "##main_profile", "Profile: " .. profile.name) then
            for i, p in ipairs(config.profiles) do
                local is_selected = (i == idx)
                if r.ImGui_Selectable(ctx, p.name, is_selected) then
                    if i ~= idx then
                        if state.track_ptr and r.ValidatePtr(state.track_ptr, "MediaTrack*") then
                            local current_chunk = GetTrackChunk(state.track_ptr)
                            if current_chunk then
                                local current_normalized = NormalizeChunkForComparison(current_chunk)
                                if current_normalized ~= state.last_normalized_chunk then
                                    AddToUndoHistory(current_chunk)
                                    state.last_chunk = current_chunk
                                    state.last_normalized_chunk = current_normalized
                                    SaveTrackData()
                                end
                            end
                        end
                        
                        config.active_profile = i
                        SaveConfig()
                        state.track_ptr = nil
                        state.track_guid = nil
                        state.is_monitoring = false
                        state.undo_history = {}
                        state.undo_index = 0
                        state.last_chunk = nil
                        state.last_normalized_chunk = nil
                        last_file_timestamp = nil
                        LoadOrCreateTrack()
                        SetStatus("Switched to profile: " .. p.name)
                    end
                end
                if is_selected then
                    r.ImGui_SetItemDefaultFocus(ctx)
                end
            end
            r.ImGui_EndCombo(ctx)
        end
    end
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
                config.show_settings = not config.show_settings
                SaveConfig()
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

local function DrawSettingsGeneralTab()
    local changed, new_val
    
    r.ImGui_Spacing(ctx)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.accent)
    r.ImGui_Text(ctx, "GENERAL SETTINGS")
    r.ImGui_PopStyleColor(ctx)
    r.ImGui_Separator(ctx)
    
    r.ImGui_Text(ctx, "Max undo history:")
    r.ImGui_SameLine(ctx, 140)
    r.ImGui_SetNextItemWidth(ctx, -1)
    changed, new_val = r.ImGui_SliderInt(ctx, "##maxundo", config.max_undo_history, 10, 200)
    if changed then config.max_undo_history = new_val; SaveConfig() end
    
    r.ImGui_Text(ctx, "Auto-saves to keep:")
    r.ImGui_SameLine(ctx, 140)
    r.ImGui_SetNextItemWidth(ctx, -1)
    changed, new_val = r.ImGui_SliderInt(ctx, "##backups", config.auto_backup_count, 1, 20)
    if changed then config.auto_backup_count = new_val; SaveConfig() end
    
    r.ImGui_Spacing(ctx)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.accent)
    r.ImGui_Text(ctx, "TRACK PREFIX")
    r.ImGui_PopStyleColor(ctx)
    r.ImGui_Separator(ctx)
    
    changed, new_val = r.ImGui_Checkbox(ctx, "Enable prefix", config.track_prefix_enabled)
    if changed then config.track_prefix_enabled = new_val; SaveConfig() end
    
    if config.track_prefix_enabled then
        r.ImGui_Text(ctx, "Prefix:")
        r.ImGui_SameLine(ctx, 80)
        r.ImGui_SetNextItemWidth(ctx, -1)
        changed, new_val = r.ImGui_InputText(ctx, "##prefix", config.track_prefix or "IT: ")
        if changed then config.track_prefix = new_val; SaveConfig() end
    end
    
    r.ImGui_Spacing(ctx)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.accent)
    r.ImGui_Text(ctx, "TEMPO")
    r.ImGui_PopStyleColor(ctx)
    r.ImGui_Separator(ctx)
    
    r.ImGui_Text(ctx, "On tempo mismatch, preserve:")
    r.ImGui_SameLine(ctx, 200)
    if r.ImGui_RadioButton(ctx, "Time", config.tempo_mode == "time") then
        config.tempo_mode = "time"; SaveConfig()
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, "Beat", config.tempo_mode == "beat") then
        config.tempo_mode = "beat"; SaveConfig()
    end
    
    r.ImGui_Spacing(ctx)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.accent)
    r.ImGui_Text(ctx, "DISPLAY")
    r.ImGui_PopStyleColor(ctx)
    r.ImGui_Separator(ctx)
    
    local icon_size = config.compact_icon_size or 28
    r.ImGui_Text(ctx, "Icon size:")
    r.ImGui_SameLine(ctx, 80)
    r.ImGui_SetNextItemWidth(ctx, -1)
    local size_changed, size_val = r.ImGui_SliderInt(ctx, "##iconsize", icon_size, 16, 64)
    if size_changed then config.compact_icon_size = size_val; SaveConfig() end
    
    local is_locked = config.compact_lock_position
    if is_locked then
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_Alpha(), 0.4)
    end
    
    r.ImGui_Text(ctx, "Offset X:")
    r.ImGui_SameLine(ctx, 80)
    r.ImGui_SetNextItemWidth(ctx, -70)
    local offset_changed, offset_val = r.ImGui_SliderInt(ctx, "##offsetx", config.compact_offset_x or -40, -300, 100)
    if offset_changed and not is_locked then config.compact_offset_x = offset_val; SaveConfig() end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "-##xm", 30, 0) and not is_locked then config.compact_offset_x = (config.compact_offset_x or -40) - 1; SaveConfig() end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "+##xp", 30, 0) and not is_locked then config.compact_offset_x = (config.compact_offset_x or -40) + 1; SaveConfig() end
    
    r.ImGui_Text(ctx, "Offset Y:")
    r.ImGui_SameLine(ctx, 80)
    r.ImGui_SetNextItemWidth(ctx, -70)
    local offset_y_changed, offset_y_val = r.ImGui_SliderInt(ctx, "##offsety", config.compact_offset_y or 2, -50, 50)
    if offset_y_changed and not is_locked then config.compact_offset_y = offset_y_val; SaveConfig() end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "-##ym", 30, 0) and not is_locked then config.compact_offset_y = (config.compact_offset_y or 2) - 1; SaveConfig() end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "+##yp", 30, 0) and not is_locked then config.compact_offset_y = (config.compact_offset_y or 2) + 1; SaveConfig() end
    
    if is_locked then
        r.ImGui_PopStyleVar(ctx)
    end
    
    changed, new_val = r.ImGui_Checkbox(ctx, "Lock position", config.compact_lock_position)
    if changed then 
        config.compact_lock_position = new_val
        if new_val then
            local active_profile = GetActiveProfile()
            local pstate = profile_states[GetProfileStateKey(active_profile)]
            if pstate and pstate.track_ptr then
                local bounds = GetTrackTCPBounds(pstate.track_ptr, ctx)
                if bounds then
                    config.compact_locked_x = bounds.x + (config.compact_offset_x or -40)
                    config.compact_locked_y = config.compact_offset_y or 2
                end
            end
        end
        SaveConfig() 
    end
    
    r.ImGui_SameLine(ctx)
    changed, new_val = r.ImGui_Checkbox(ctx, "No background", config.compact_no_bg)
    if changed then config.compact_no_bg = new_val; SaveConfig() end
    
    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)
    
    local btn_w = r.ImGui_GetContentRegionAvail(ctx)
    if r.ImGui_Button(ctx, "Hide Settings (show icons only)", btn_w, 28) then
        config.hide_window = true
        SaveConfig()
    end
end

local function DrawSettingsTrackTab(profile_index)
    local profile = config.profiles[profile_index]
    if not profile then return end
    
    local profile_key = GetProfileStateKey(profile)
    local pstate = profile_states[profile_key]
    local changed, new_val
    
    r.ImGui_Spacing(ctx)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.accent)
    r.ImGui_Text(ctx, "TRACK SETTINGS")
    r.ImGui_PopStyleColor(ctx)
    r.ImGui_Separator(ctx)
    
    local enabled = profile.enabled or false
    local checkbox_changed, new_enabled = r.ImGui_Checkbox(ctx, "##enabled", enabled)
    if checkbox_changed then
        ToggleProfile(profile_index, new_enabled)
        state.force_tab_select = true
    end
    
    r.ImGui_SameLine(ctx)
    local checkbox_end_x = r.ImGui_GetCursorPosX(ctx)
    local color_picker_width = 30
    local avail_for_name = r.ImGui_GetContentRegionAvail(ctx) - color_picker_width - 8
    r.ImGui_SetNextItemWidth(ctx, avail_for_name)
    local name_changed, new_name = r.ImGui_InputText(ctx, "##trackname", profile.name, r.ImGui_InputTextFlags_EnterReturnsTrue())
    if name_changed and new_name ~= "" then
        profile.name = new_name
        if pstate and pstate.track_ptr and r.ValidatePtr(pstate.track_ptr, "MediaTrack*") then
            r.GetSetMediaTrackInfo_String(pstate.track_ptr, "P_NAME", GetFullTrackName(profile), true)
        end
        SaveConfig()
        state.force_tab_select = true
    end
    
    r.ImGui_SameLine(ctx)
    local color_stored = profile.track_color or 0x1E5A8A
    local color_changed, new_color = r.ImGui_ColorEdit3(ctx, "##trackcolor", color_stored, r.ImGui_ColorEditFlags_NoInputs())
    if color_changed then
        profile.track_color = new_color
        if pstate and pstate.track_ptr and r.ValidatePtr(pstate.track_ptr, "MediaTrack*") then
            local native_color = r.ImGui_ColorConvertNative(new_color)
            r.SetTrackColor(pstate.track_ptr, native_color | 0x1000000)
        end
        SaveConfig()
    end
    
    r.ImGui_Spacing(ctx)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.accent)
    r.ImGui_Text(ctx, "UNDO / REDO")
    r.ImGui_PopStyleColor(ctx)
    r.ImGui_Separator(ctx)
    
    local total_history = pstate and pstate.undo_history and #pstate.undo_history or 0
    local undo_idx = pstate and pstate.undo_index or total_history
    local undo_count = undo_idx - 1
    local redo_count = total_history - undo_idx
    local can_undo = profile.enabled and undo_count > 0
    local can_redo = profile.enabled and redo_count > 0
    
    r.ImGui_Text(ctx, string.format("Position: %d / %d  |  Undo: %d  |  Redo: %d", undo_idx, total_history, undo_count, redo_count))
    
    local avail_w = r.ImGui_GetContentRegionAvail(ctx)
    local half_w = (avail_w - 8) / 2
    
    if not can_undo then
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_Alpha(), 0.3)
    end
    if r.ImGui_Button(ctx, "<< Undo", half_w, 26) and can_undo then
        UndoTrackForProfile(profile)
    end
    if not can_undo then
        r.ImGui_PopStyleVar(ctx)
    end
    
    r.ImGui_SameLine(ctx)
    
    if not can_redo then
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_Alpha(), 0.3)
    end
    if r.ImGui_Button(ctx, "Redo >>", half_w, 26) and can_redo then
        RedoTrackForProfile(profile)
    end
    if not can_redo then
        r.ImGui_PopStyleVar(ctx)
    end
    
    r.ImGui_Spacing(ctx)
    
    if total_history > 0 then
        local list_open = state.history_list_open == profile_index
        local btn_width = r.ImGui_GetContentRegionAvail(ctx) - 70
        if r.ImGui_Button(ctx, list_open and "Hide History ▲" or "Show History ▼ (" .. total_history .. ")", btn_width, 0) then
            if list_open then
                state.history_list_open = nil
            else
                state.history_list_open = profile_index
            end
        end
        r.ImGui_SameLine(ctx)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x882222FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xAA3333FF)
        if r.ImGui_Button(ctx, "Clear##history", 65, 0) then
            if pstate then
                pstate.undo_history = {}
                pstate.undo_index = 0
                state.history_list_open = nil
                SetStatus("History cleared: " .. profile.name)
            end
        end
        r.ImGui_PopStyleColor(ctx, 2)
        
        if list_open and pstate and pstate.undo_history then
            local history = pstate.undo_history
            local current_idx = pstate.undo_index or 0
            
            if r.ImGui_BeginChild(ctx, "##historylist", -1, 100, 1) then
                for i = #history, 1, -1 do
                    local entry = history[i]
                    local is_current = (i == current_idx)
                    local is_redo = (i > current_idx)
                    
                    local desc = entry.description or "Track modified"
                    local time = entry.timestamp or ""
                    
                    local marker = "  "
                    if is_current then
                        marker = "> "
                    end
                    
                    local label = string.format("%s%d. %s  [%s]", marker, i, desc, time)
                    
                    if is_current then
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.accent)
                    elseif is_redo then
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x888888FF)
                    end
                    
                    if r.ImGui_Selectable(ctx, label, is_current) then
                        if i ~= current_idx then
                            JumpToHistoryForProfile(profile, i)
                        end
                    end
                    
                    if is_current or is_redo then
                        r.ImGui_PopStyleColor(ctx)
                    end
                end
                r.ImGui_EndChild(ctx)
            end
        end
    else
        r.ImGui_TextDisabled(ctx, "No history yet")
    end
    
    r.ImGui_Spacing(ctx)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.accent)
    r.ImGui_Text(ctx, "SAVE / LOAD")
    r.ImGui_PopStyleColor(ctx)
    r.ImGui_Separator(ctx)
    
    local save_avail_w = r.ImGui_GetContentRegionAvail(ctx)
    local save_half_w = (save_avail_w - 8) / 2
    
    if not profile.enabled then
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_Alpha(), 0.3)
    end
    
    if r.ImGui_Button(ctx, "Save Now", save_half_w, 26) and profile.enabled then
        if pstate and pstate.track_ptr and r.ValidatePtr(pstate.track_ptr, "MediaTrack*") then
            local chunk = GetTrackChunk(pstate.track_ptr)
            if chunk then
                SaveTrackDataForProfile(profile, pstate.track_ptr, chunk)
                SetStatus("Track saved: " .. profile.name)
            end
        end
    end
    
    r.ImGui_SameLine(ctx)
    
    if r.ImGui_Button(ctx, "Load Track", save_half_w, 26) and profile.enabled then
        local data = LoadTrackDataForProfile(profile)
        if data and data.chunk and pstate and pstate.track_ptr and r.ValidatePtr(pstate.track_ptr, "MediaTrack*") then
            r.SetTrackStateChunk(pstate.track_ptr, data.chunk, false)
            SetStatus("Track reloaded: " .. profile.name)
        end
    end
    
    if not profile.enabled then
        r.ImGui_PopStyleVar(ctx)
    end
    
    r.ImGui_Spacing(ctx)
    
    local profile_backups = ScanBackupsForProfile(profile)
    if #profile_backups > 0 then
        local list_open = state.autosave_list_open == profile_index
        local btn_width = r.ImGui_GetContentRegionAvail(ctx) - 70
        if r.ImGui_Button(ctx, list_open and "Hide Auto-Saves ▲" or "Show Auto-Saves ▼ (" .. #profile_backups .. ")", btn_width, 0) then
            if list_open then
                state.autosave_list_open = nil
            else
                state.autosave_list_open = profile_index
            end
        end
        r.ImGui_SameLine(ctx)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x882222FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xAA3333FF)
        if r.ImGui_Button(ctx, "Clear##autosaves", 65, 0) then
            for _, backup in ipairs(profile_backups) do
                os.remove(backup.path)
            end
            state.autosave_list_open = nil
            SetStatus("Auto-saves cleared: " .. profile.name)
        end
        r.ImGui_PopStyleColor(ctx, 2)
        
        if list_open then
            if r.ImGui_BeginChild(ctx, "##autosavelist" .. profile_index, -1, 100, 1) then
                for _, backup in ipairs(profile_backups) do
                    r.ImGui_PushID(ctx, backup.path)
                    if r.ImGui_Selectable(ctx, backup.timestamp, false) then
                        if profile.enabled then
                            LoadBackupForProfile(profile, backup)
                        end
                    end
                    r.ImGui_PopID(ctx)
                end
                r.ImGui_EndChild(ctx)
            end
        end
    else
        r.ImGui_TextDisabled(ctx, "No auto-saves yet")
    end
    
    r.ImGui_Spacing(ctx)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.accent)
    r.ImGui_Text(ctx, "SNAPSHOTS")
    r.ImGui_PopStyleColor(ctx)
    r.ImGui_Separator(ctx)
    
    local snap_avail_w = r.ImGui_GetContentRegionAvail(ctx)
    local snap_half_w = (snap_avail_w - 8) / 2
    
    if not profile.enabled then
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_Alpha(), 0.3)
    end
    
    r.ImGui_SetNextItemWidth(ctx, snap_half_w)
    local name_input_changed
    name_input_changed, state.snapshot_name_input = r.ImGui_InputTextWithHint(ctx, "##snapname", "Snapshot name...", state.snapshot_name_input or "")
    
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Save Snapshot", snap_half_w, 0) and profile.enabled then
        local snap_name = state.snapshot_name_input ~= "" and state.snapshot_name_input or (profile.name .. " Snapshot")
        if SaveSnapshotForProfile(profile, snap_name) then
            state.snapshot_name_input = ""
        end
    end
    
    if not profile.enabled then
        r.ImGui_PopStyleVar(ctx)
    end
    
    local profile_snapshots = ScanSnapshotsForProfile(profile)
    if #profile_snapshots > 0 then
        for _, snap in ipairs(profile_snapshots) do
            r.ImGui_PushID(ctx, snap.path)
            if r.ImGui_Selectable(ctx, snap.name .. " (" .. snap.timestamp .. ")") and profile.enabled then
                LoadSnapshotForProfile(profile, snap)
            end
            if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseClicked(ctx, 1) then
                DeleteSnapshotForProfile(profile, snap)
            end
            r.ImGui_PopID(ctx)
        end
    else
        r.ImGui_TextDisabled(ctx, "No snapshots saved yet")
    end
end

local function DrawSettingsUI()
    DrawCloseButton()
    
    if not settings_shield_image or not r.ImGui_ValidatePtr(settings_shield_image, "ImGui_Image*") then
        local img_path = SCRIPT_PATH .. "/ISHIELD.png"
        settings_shield_image = r.ImGui_CreateImage(img_path)
        if settings_shield_image then
            r.ImGui_Attach(ctx, settings_shield_image)
        end
    end
    
    if not settings_header_font or not r.ImGui_ValidatePtr(settings_header_font, "ImGui_Font*") then
        settings_header_font = r.ImGui_CreateFont("Segoe UI Bold", 22)
        r.ImGui_Attach(ctx, settings_header_font)
    end
    
    local shield_size = 48
    local font_size = 22
    
    local total_width = shield_size + 10 + 220
    local avail_w = r.ImGui_GetContentRegionAvail(ctx)
    local start_x = (avail_w - total_width) / 2
    
    local start_y = r.ImGui_GetCursorPosY(ctx)
    r.ImGui_SetCursorPosX(ctx, start_x)
    
    if settings_shield_image then
        r.ImGui_Image(ctx, settings_shield_image, shield_size, shield_size)
        r.ImGui_SameLine(ctx)
    end
    
    r.ImGui_PushFont(ctx, settings_header_font, font_size)
    local text_y = start_y + (shield_size - font_size) / 2 - 5
    r.ImGui_SetCursorPosY(ctx, text_y)
    r.ImGui_Text(ctx, "Indestructible Track(s)")
    r.ImGui_PopFont(ctx)
    
    r.ImGui_SetCursorPosY(ctx, start_y + shield_size)
    
    local general_tab_color = 0x3A3A3AFF
    local use_force_select = state.force_tab_select
    state.force_tab_select = false
    
    if r.ImGui_BeginTabBar(ctx, "SettingsTabs") then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Tab(), general_tab_color)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TabHovered(), 0x4A4A4AFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TabSelected(), 0x5A5A5AFF)
        
        local general_flags = (use_force_select and state.settings_tab == 0) and r.ImGui_TabItemFlags_SetSelected() or r.ImGui_TabItemFlags_None()
        if r.ImGui_BeginTabItem(ctx, "  General  ##tab0", nil, general_flags) then
            state.settings_tab = 0
            r.ImGui_PopStyleColor(ctx, 3)
            DrawSettingsGeneralTab()
            r.ImGui_EndTabItem(ctx)
        else
            r.ImGui_PopStyleColor(ctx, 3)
        end
        
        for i, profile in ipairs(config.profiles) do
            local enabled = profile.enabled or false
            local track_color = profile.track_color or 0x1E5A8A
            local tab_color, tab_hover, tab_active
            
            if enabled then
                tab_color = ((track_color & 0xFFFFFF) << 8) | 0x80
                tab_hover = ((track_color & 0xFFFFFF) << 8) | 0xC0
                tab_active = ((track_color & 0xFFFFFF) << 8) | 0xFF
            else
                tab_color = 0x2A2A2AFF
                tab_hover = 0x3A3A3AFF
                tab_active = 0x4A4A4AFF
            end
            
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Tab(), tab_color)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TabHovered(), tab_hover)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TabSelected(), tab_active)
            
            local tab_label = "  " .. profile.name .. "  ##tab" .. i
            local tab_flags = (use_force_select and state.settings_tab == i) and r.ImGui_TabItemFlags_SetSelected() or r.ImGui_TabItemFlags_None()
            
            if r.ImGui_BeginTabItem(ctx, tab_label, nil, tab_flags) then
                state.settings_tab = i
                r.ImGui_PopStyleColor(ctx, 3)
                DrawSettingsTrackTab(i)
                r.ImGui_EndTabItem(ctx)
            else
                r.ImGui_PopStyleColor(ctx, 3)
            end
        end
        
        r.ImGui_EndTabBar(ctx)
    end
end

local function loop()
    UpdateCachedChunk()
    
    if state.track_ptr and not r.ValidatePtr(state.track_ptr, "MediaTrack*") then
        local found_track = FindIndestructibleTrack()
        if found_track then
            state.track_ptr = found_track
            state.track_guid = r.GetTrackGUID(found_track)
            state.last_chunk = GetTrackChunk(found_track)
            state.last_normalized_chunk = NormalizeChunkForComparison(state.last_chunk)
        else
            state.track_ptr = nil
            state.track_guid = nil
            state.is_monitoring = false
        end
    end
    
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
    if now - state.last_check_time >= 0.1 then
        state.last_check_time = now
        CheckForExternalChanges()
        CheckAllProfilesForChanges()
        CheckExternalToggleRequests()
    end
    
    if config.compact_mode then
        local keep_running = DrawCompactWidget()
        if keep_running then
            r.defer(loop)
        else
            SaveConfig()
        end
        return
    end
    
    if config.preview_compact then
        DrawCompactWidget()
    end
    
    if config.hide_window then
        r.defer(loop)
        return
    end
    
    ApplyTheme()
    r.ImGui_PushFont(ctx, main_font, 13)
    
    local window_flags = r.ImGui_WindowFlags_NoCollapse() | r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_AlwaysAutoResize()
    
    local win_w = 380
    r.ImGui_SetNextWindowSizeConstraints(ctx, win_w, 0, win_w, 800)
    
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowBorderSize(), 1)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), 0x505050FF)
    
    local visible, open = r.ImGui_Begin(ctx, SCRIPT_NAME, true, window_flags)
    
    if not open then
        state.close_action = "exit"
    end
    
    if visible then
        if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape()) then
            open = false
            state.close_action = "exit"
        end
        
        if state.close_action == "exit" then
            open = false
        end
        
        DrawSettingsUI()
        r.ImGui_End(ctx)
    end
    
    r.ImGui_PopStyleColor(ctx)
    r.ImGui_PopStyleVar(ctx)
    r.ImGui_PopFont(ctx)
    PopTheme()
    
    if open then
        r.defer(loop)
    else
        SaveConfig()
    end
end

local function OnExit()
    if COMMAND_ID then
        r.SetToggleCommandState(0, COMMAND_ID, 0)
        r.RefreshToolbar2(0, COMMAND_ID)
    end
    
    for _, profile in ipairs(config.profiles) do
        if IsProfileEnabled(profile) then
            local profile_key = GetProfileStateKey(profile)
            local pstate = profile_states[profile_key]
            if pstate and pstate.track_ptr and r.ValidatePtr(pstate.track_ptr, "MediaTrack*") then
                local chunk = GetTrackChunk(pstate.track_ptr)
                if chunk then
                    SaveTrackDataForProfile(profile, pstate.track_ptr, chunk)
                end
            end
        end
    end
    
    r.PreventUIRefresh(1)
    RemoveITTracksFromAllProjects()
    r.PreventUIRefresh(-1)
    r.TrackList_AdjustWindows(false)
    
    SaveConfig()
end

local function Init()
    EnsureDirectories()
    LoadConfig()
    
    for i = 1, 4 do
        if config.profiles and config.profiles[i] then
            r.SetExtState("TK_IndestructibleTrack", "state_profile_" .. i, config.profiles[i].enabled and "1" or "0", false)
        end
    end
    
    local _, _, section_id, cmd_id = r.get_action_context()
    if cmd_id and cmd_id ~= 0 then
        COMMAND_ID = cmd_id
        r.SetToggleCommandState(section_id, cmd_id, 1)
        r.RefreshToolbar2(section_id, cmd_id)
    end
    
    last_project_ptr = r.EnumProjects(-1)
    cached_project_ptr = last_project_ptr
    
    local active_profile = GetActiveProfile()
    local active_profile_key = GetProfileStateKey(active_profile)
    
    for _, profile in ipairs(config.profiles) do
        if IsProfileEnabled(profile) then
            local profile_key = GetProfileStateKey(profile)
            local pstate = GetOrCreateProfileState(profile)
            
            local track = CheckInitialConflictForProfile(profile)
            if not track then
                track = LoadOrCreateTrackForProfile(profile)
            end
            
            if track then
                pstate.track_ptr = track
                pstate.track_guid = r.GetTrackGUID(track)
                local chunk = GetTrackChunk(track)
                if chunk then
                    pstate.last_chunk = chunk
                    pstate.last_normalized_chunk = NormalizeChunkForComparison(chunk)
                    cached_chunks_per_profile[profile_key] = {
                        chunk = chunk,
                        normalized = pstate.last_normalized_chunk,
                        tempo = r.Master_GetTempo()
                    }
                    if #pstate.undo_history == 0 then
                        AddToUndoHistoryForProfile(profile, chunk)
                    end
                end
                
                if profile_key == active_profile_key then
                    state.track_ptr = track
                    state.track_guid = pstate.track_guid
                    state.last_chunk = pstate.last_chunk
                    state.last_normalized_chunk = pstate.last_normalized_chunk
                    state.is_monitoring = true
                end
            end
        end
    end
    r.TrackList_AdjustWindows(false)
    
    if state.track_ptr then
        state.last_project_state = r.GetProjectStateChangeCount(0)
        local chunk = GetTrackChunk(state.track_ptr)
        if chunk then
            cached_chunk_for_switch = chunk
            cached_normalized_for_switch = NormalizeChunkForComparison(chunk)
        end
    end
    
    r.atexit(OnExit)
    r.defer(loop)
end

Init()
