-- @description TK Automation Item Manager (AIM)
-- @version 0.1.0
-- @author TouristKiller
-- @about
--   Automation Item Manager with visual previews and ReaCurve integration
-- @changelog:
--   v0.1.0 — ReaCurve Integration Update
--   + ScaleConverter for accurate Volume/Pitch/Tempo envelope handling
--   + Envelope range detection via state chunk (MINVAL/MAXVAL)
--   + Time selection support (fit automation items to selection)
--   + Take FX envelope support
--   + Export envelope points to .ReaperAutoItem file
--   + ReaCurve MORPH bridge (send curve to Slot A/B)
--   + Select for SCULPT option
--   + PreventUIRefresh for heavy operations

-- THANX TO MPL FOR ALL THE THINGS HE DOES FOR THE REAPER COMMUNITY!! (I Used code inspired by MPL to do the conversions)
-- ScaleConverter logic inspired by sailok's ReaCurve Suite (EnvConvert/ScaleConverter)
-------------------------------------------------------------------------------------------------------
local r = reaper
local script_name = "TK AIM"

if not r.ImGui_CreateContext then
    r.ShowMessageBox("ReaImGui extension required.", "Missing Extension", 0)
    return
end

local script_path = debug.getinfo(1, "S").source:match("@?(.*[/\\])")
package.path = script_path .. "?.lua;" .. package.path

local json_ok, json = pcall(require, "json_aim")
if not json_ok then
    json = {
        encode = function(t) return "" end,
        decode = function(s) return {} end
    }
end

local ctx = r.ImGui_CreateContext(script_name)
local automation_items = {}
local startup_warnings = {}

function ValidateContext()

    if not ctx or not r.ImGui_ValidatePtr(ctx, 'ImGui_Context*') then
        ctx = r.ImGui_CreateContext(script_name)
    end
    return ctx
end

function VF_CheckReaperVrs(rvrs, showmsg) 
    local vrs_num = r.GetAppVersion()
    vrs_num = tonumber(vrs_num:match('[%d%.]+'))
    if rvrs > vrs_num then 
    if showmsg then SetFooterMessage('Update REAPER to newer version ('..rvrs..' or newer)') end
        return
    else
        return true
    end
end
local cache_file = script_path .. "automation_cache.json"
local settings_file = script_path .. "automation_settings.json"
local automation_folder = r.GetResourcePath() .. "/AutomationItems"
local automation_folder_exists = false

local preview_width = 120
local preview_height = 60
local FOOTER_H = 140
local INFO_H = 45

local enable_loop = false
local color_scheme = "green_yellow"  
local show_lines_only = false  
local move_edit_cursor = false
local use_time_selection = true
local show_tooltips = true

local curve_color = 0x00FF00FF   
local points_color = 0xFFFF00FF  

local footer_message = ""
local footer_message_time = 0
local footer_message_duration = 4.0  
local has_sws = reaper and reaper.BR_GetMouseCursorContext ~= nil
local is_dragging = false
local drag_item = nil
local drag_hover_env = nil
local drag_hover_pos = nil
local drag_hover_name = nil

function SetFooterMessage(msg)
    footer_message = msg
    footer_message_time = r.time_precise()
end

function Tooltip(text)
    if show_tooltips and r.ImGui_IsItemHovered(ctx) then
        r.ImGui_BeginTooltip(ctx)
        r.ImGui_Text(ctx, text)
        r.ImGui_EndTooltip(ctx)
    end
end

---------------------------------------------------
-- Cache functies
---------------------------------------------------

function SaveCache()
    if not json_ok then return end
    local file = io.open(cache_file, "w")
    if file then
        file:write(json.encode(automation_items))
        file:close()
    end
end

function SaveSettings()
    local settings = {
        enable_loop = enable_loop,
        color_scheme = color_scheme,
        show_lines_only = show_lines_only,
        move_edit_cursor = move_edit_cursor,
        use_time_selection = use_time_selection,
        show_tooltips = show_tooltips,
        curve_color = curve_color,
        points_color = points_color
    }
    
    local file = io.open(settings_file, "w")
    if file then
        file:write(json.encode(settings))
        file:close()
    end
end

function LoadSettings()
    local file = io.open(settings_file, "r")
    if file then
        local content = file:read("*all")
        file:close()
        content = content:gsub("^\239\187\191", "")
        local ok, settings = pcall(json.decode, content)
        if not ok or not settings or type(settings) ~= "table" then
            os.remove(settings_file)
            return false
        end
        if settings and type(settings) == "table" then
            enable_loop = settings.enable_loop or false
            color_scheme = settings.color_scheme or "green_yellow"
            show_lines_only = settings.show_lines_only or false
            move_edit_cursor = settings.move_edit_cursor or false
            if settings.use_time_selection ~= nil then use_time_selection = settings.use_time_selection else use_time_selection = true end
            if settings.show_tooltips ~= nil then show_tooltips = settings.show_tooltips else show_tooltips = true end
            if settings.curve_color then curve_color = settings.curve_color end
            if settings.points_color then points_color = settings.points_color end
            return true
        end
    end
    return false
end

---------------------------------------------------
-- Utility functies
---------------------------------------------------

function GetEnvelopeType(envelope)
    if not envelope then return "unknown" end
    
    local retval, env_name = r.GetEnvelopeName(envelope)
    if not retval then return "unknown" end
    
    env_name = env_name:lower()
    
    if env_name:match("volume") or env_name:match("vol") or env_name:match("track volume") then
        return "volume"
    end
    
    if env_name:match("pan") or env_name:match("track pan") then
        return "pan"
    end

    if env_name:match("mute") or env_name:match("track mute") then
        return "mute"
    end

    if env_name:match("pitch") or env_name:match("item pitch") then
        return "pitch"
    end
    
    if env_name:match("send") then
        return "send"
    end
    
    if env_name:match("fx") or env_name:match("vst") or env_name:match("param") then
        return "fxparam"
    end
    
    return "unknown"
end

---------------------------------------------------
-- ScaleConverter (gebaseerd op sailok's ReaCurve)
---------------------------------------------------

local SC = {}
SC.__index = SC

local VOL_PARAMS = {
    [3] = { split = 1.0000, n = 3.3219, max_db = 0 },
    [2] = { split = 0.8421, n = 3.3180, max_db = 6 },
    [6] = { split = 0.7083, n = 3.3164, max_db = 12 },
    [7] = { split = 0.5387, n = 3.4490, max_db = 24 },
}

function SC.newVolume()
    local raw = 7
    if r.SNM_GetIntConfigVar then
        raw = r.SNM_GetIntConfigVar("volenvrange", 0)
    end
    local p = VOL_PARAMS[raw] or VOL_PARAMS[7]
    local self = setmetatable({}, SC)
    self.type = "volume"
    self.max_db = p.max_db
    self.max_gain = 10.0 ^ (p.max_db / 20.0)
    self.split = p.split
    self.n = p.n
    return self
end

function SC.newPitch()
    local range = 12
    if r.SNM_GetIntConfigVar then
        local raw = r.SNM_GetIntConfigVar("pitchenvrange", 0)
        local val = raw & 0xFF
        if val > 0 then range = val end
    end
    local self = setmetatable({}, SC)
    self.type = "pitch"
    self.range = range
    return self
end

function SC.newTempo()
    local t_min, t_max = 60, 180
    if r.SNM_GetIntConfigVar then
        local mn = r.SNM_GetIntConfigVar("tempoenvmin", -1)
        local mx = r.SNM_GetIntConfigVar("tempoenvmax", -1)
        if mn > 0 then t_min = mn end
        if mx > 0 then t_max = mx end
    end
    local self = setmetatable({}, SC)
    self.type = "tempo"
    self.t_min = t_min
    self.t_max = t_max
    return self
end

function SC:toNative(v)
    if self.type == "volume" then
        if v <= 0 then return 0.0 end
        if v >= 1 then return self.max_gain end
        if v <= self.split then
            return (v / self.split) ^ self.n
        else
            local db = (v - self.split) / (1.0 - self.split) * self.max_db
            return 10.0 ^ (db / 20.0)
        end
    elseif self.type == "pitch" then
        return (math.max(0, math.min(1, v)) * 2.0 - 1.0) * self.range
    elseif self.type == "tempo" then
        return self.t_min + math.max(0, math.min(1, v)) * (self.t_max - self.t_min)
    end
end

function SC:fromNative(native)
    if self.type == "volume" then
        if native <= 0 then return 0.0 end
        if native >= self.max_gain then return 1.0 end
        if native <= 1.0 then
            return self.split * (native ^ (1.0 / self.n))
        else
            local db = math.log(native) / math.log(10) * 20.0
            return self.split + (1.0 - self.split) * db / self.max_db
        end
    elseif self.type == "pitch" then
        return (math.max(-self.range, math.min(self.range, native)) / self.range + 1.0) / 2.0
    elseif self.type == "tempo" then
        return (math.max(self.t_min, math.min(self.t_max, native)) - self.t_min) / (self.t_max - self.t_min)
    end
end

function SC:toEnvelope(linear_val, scaling_mode)
    return r.ScaleToEnvelopeMode(scaling_mode, self:toNative(linear_val))
end

function SC:fromEnvelope(env_val, scaling_mode)
    return self:fromNative(r.ScaleFromEnvelopeMode(scaling_mode, env_val))
end

---------------------------------------------------
-- Envelope value conversion (ReaCurve-compatibel)
---------------------------------------------------

function ToEnvValue(v, conv, lo, hi, mode)
    if conv then
        if conv.type == "volume" then return conv:toEnvelope(v, mode)
        else return conv:toNative(v) end
    end
    local v_fader = (mode == 1) and v or (lo + v * (hi - lo))
    return r.ScaleToEnvelopeMode(mode, v_fader)
end

function FromEnvValue(v_raw, conv, lo, hi, mode)
    local result
    if conv then
        if conv.type == "volume" then result = conv:fromEnvelope(v_raw, mode)
        else result = conv:fromNative(v_raw) end
    else
        local vf = r.ScaleFromEnvelopeMode(mode, v_raw)
        if mode == 1 then result = vf
        else
            local range = hi - lo
            if math.abs(range) < 1e-9 then result = 0.5
            else result = (vf - lo) / range end
        end
    end
    if result ~= result or result >= math.huge or result <= -math.huge then return 0.0 end
    return result
end

function GetEnvelopeInfo(env)
    if not env then return nil end
    local _, env_name = r.GetEnvelopeName(env)
    env_name = env_name or ""

    local mode = r.GetEnvelopeScalingMode(env)

    local conv = nil
    if env_name == "Volume" or env_name == "Volume (Pre-FX)" then
        conv = SC.newVolume()
    elseif env_name == "Pitch" then
        conv = SC.newPitch()
    elseif env_name == "Tempo map" or env_name == "Tempo" then
        conv = SC.newTempo()
    end

    local lo, hi = 0, 1
    if mode ~= 1 then
        local ok, chunk = r.GetEnvelopeStateChunk(env, "", false)
        if ok and chunk then
            local mn = chunk:match("\nMINVAL ([%-%.%d]+)")
            local mx = chunk:match("\nMAXVAL ([%-%.%d]+)")
            if mn and mx then
                local clo, chi = tonumber(mn), tonumber(mx)
                if chi - clo > 1e-9 then lo = clo; hi = chi end
            end
        end
        if env_name == "Pan" or env_name == "Pan (Pre-FX)" then lo = -1; hi = 1
        elseif env_name == "Width" or env_name == "Width (Pre-FX)" then lo = -1; hi = 1
        end
    end

    local pmin = r.GetEnvelopeInfo_Value(env, "PARM_MIN")
    local pmax = r.GetEnvelopeInfo_Value(env, "PARM_MAX")
    if pmin and pmax and (pmax - pmin) > 1e-9 then
        lo = pmin; hi = pmax
    end

    return {
        name = env_name,
        conv = conv,
        lo = lo,
        hi = hi,
        mode = mode,
    }
end

function NormalizeSourceValue(value, source_type)
    if source_type == "pan_or_bipolar" then
        return (value + 1.0) / 2.0
    elseif source_type == "volume_or_gain" and value > 1.0 then
        local vol_conv = SC.newVolume()
        return vol_conv:fromNative(value)
    end
    return math.max(0, math.min(1, value))
end

---------------------------------------------------
-- Target envelope resolution (track + take support)
---------------------------------------------------

function ResolveTargetEnvelope()
    local sel_env = r.GetSelectedEnvelope(0)
    if sel_env then return sel_env end

    if r.CountSelectedMediaItems(0) > 0 then
        local item = r.GetSelectedMediaItem(0, 0)
        local take = r.GetActiveTake(item)
        if take then
            for e = 0, r.CountTakeEnvelopes(take) - 1 do
                local env = r.GetTakeEnvelope(take, e)
                local ok, chunk = r.GetEnvelopeStateChunk(env, "", false)
                if ok and chunk then
                    local vis = chunk:match("\nVIS (%d)")
                    if not vis or tonumber(vis) == 1 then
                        return env
                    end
                end
            end
        end
    end

    return nil
end

---------------------------------------------------
-- Time selection support
---------------------------------------------------

function GetEffectiveRange(default_length)
    if use_time_selection then
        local ts_s, ts_e = r.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
        if (ts_e - ts_s) >= 0.01 then
            return ts_s, ts_e, true
        end
    end
    local cursor = r.GetCursorPosition()
    return cursor, cursor + (default_length or 1.0), false
end

function LoadCache()
    if not json_ok then return false end
    local file = io.open(cache_file, "r")
    if file then
        local content = file:read("*all")
        file:close()
        content = content:gsub("^\239\187\191", "")
        local ok, cached_items = pcall(json.decode, content)
        if not ok or not cached_items then
            os.remove(cache_file)
            return false
        end
        if cached_items and type(cached_items) == "table" and next(cached_items) ~= nil then
            automation_items = cached_items
            
            table.sort(automation_items, function(a, b)
                local folder_a = (a.display_folder or "Home"):lower()
                local folder_b = (b.display_folder or "Home"):lower()
                
                if folder_a ~= folder_b then
                    if folder_a == "home" then return true end
                    if folder_b == "home" then return false end
                    return folder_a < folder_b
                end
                
                local name_a = (a.name or ""):lower()
                local name_b = (b.name or ""):lower()
                return name_a < name_b
            end)
            
            return true
        end
    end
    return false
end

local dir_sep = package.config:sub(1,1)
local function path_join(a,b)
    if a:sub(-1) == '/' or a:sub(-1) == '\\' then return a..b end
    return a..dir_sep..b
end
local function normalize_path(p)
    local n = p:gsub('\\', '/')
    if n:sub(-1) == '/' then n = n:sub(1, -2) end
    return n
end
local function basename(p)
    local name = p:match("([^/\\]+)$")
    return name or p
end
local function dirname(p)
    local d = p:match("^(.*[/\\])")
    if not d then return '' end
    if d:sub(-1) == '/' or d:sub(-1) == '\\' then d = d:sub(1, -2) end
    return d
end
local function walk_autoitem_files(root)
    local results = {}
    -- quick existence probe: if parent doesn't contain root as a subdir, treat as missing
    local function walk(dir)
        local i = 0
        while true do
            local f = r.EnumerateFiles(dir, i)
            if not f then break end
            if f:lower():sub(-15) == ".reaperautoitem" then
                table.insert(results, path_join(dir, f))
            end
            i = i + 1
        end
        local j = 0
        while true do
            local sub = r.EnumerateSubdirectories(dir, j)
            if not sub then break end
            walk(path_join(dir, sub))
            j = j + 1
        end
    end
    walk(root)
    return results
end

local function AutomationFolderExists()
    local parent = dirname(automation_folder)
    local target = basename(automation_folder):lower()
    if not parent or parent == "" then return false end
    local j = 0
    while true do
        local sub = r.EnumerateSubdirectories(parent, j)
        if not sub then break end
        if sub:lower() == target then return true end
        j = j + 1
    end
    return false
end

local function OpenPathInExplorer(path)
    local osn = r.GetOS()
    if osn:match('^Win') then
        local win = path:gsub('/', '\\')
        os.execute('explorer /e,"' .. win .. '"')
    elseif osn:match('^OSX') then
        os.execute('open "' .. path .. '"')
    else
        os.execute('xdg-open "' .. path .. '"')
    end
end

local function EnsureAutomationFolderExists()
    automation_folder_exists = AutomationFolderExists()
    if automation_folder_exists then return true end
    local ret = r.ShowMessageBox("AutomationItems folder not found:\n" .. automation_folder .. "\n\nCreate it now?", script_name, 4)
    if ret == 6 then -- Yes
        local ok = r.RecursiveCreateDirectory and (r.RecursiveCreateDirectory(automation_folder, 0) == 1)
        if ok then
            automation_folder_exists = true
            SetFooterMessage("AutomationItems folder created")
            return true
        else
            SetFooterMessage("Could not create AutomationItems folder")
            return false
        end
    end
    return false
end

---------------------------------------------------
-- Automation Item functies
---------------------------------------------------

function ScanAutomationItems()
    automation_items = {}
    automation_folder_exists = AutomationFolderExists()
    if not automation_folder_exists then
        SetFooterMessage("AutomationItems folder not found at: " .. automation_folder .. " — save an automation item first or create this folder")
        return
    end
    local files = walk_autoitem_files(automation_folder)
    local norm_root = normalize_path(automation_folder)
    for _, full_path in ipairs(files) do
        local filename = basename(full_path)
        local norm_full = normalize_path(full_path)
        local relative_path = ""
        local prefix = norm_root .. "/"
        if norm_full:sub(1, #prefix) == prefix then
            relative_path = norm_full:sub(#prefix + 1)
        else
            relative_path = filename
        end
        local folder_path = relative_path:match("^(.*)/[^/]+$") or ""
        local display_folder = "Home"
        local first = folder_path:match("^([^/]+)")
        if first and first ~= "" then display_folder = first end
        local item_data = ParseAutomationFile(full_path)
        if item_data then
            item_data.name = filename:gsub("%.ReaperAutoItem$", "")
            item_data.filename = filename
            item_data.path = full_path
            item_data.folder = folder_path
            item_data.display_folder = display_folder
            item_data.relative_path = relative_path
            item_data.preview = GeneratePreview(item_data)
            table.insert(automation_items, item_data)
        end
    end
    table.sort(automation_items, function(a, b)
        local folder_a = (a.display_folder or "Home"):lower()
        local folder_b = (b.display_folder or "Home"):lower()
        if folder_a ~= folder_b then
            if folder_a == "home" then return true end
            if folder_b == "home" then return false end
            return folder_a < folder_b
        end
        local name_a = (a.name or ""):lower()
        local name_b = (b.name or ""):lower()
        return name_a < name_b
    end)
    SaveCache()
end

function ParseAutomationFile(file_path)
    if not file_path then return nil end
    
    local file = io.open(file_path, "r")
    if not file then return nil end
    
    local content = file:read("*all")
    file:close()
    
    local data = {
        points = {},
        srclen = 1.0,
        point_count = 0,
        source_file = file_path,
        source_envelope_type = "unknown",
        value_range = {min = math.huge, max = -math.huge}
    }
    
    for line in content:gmatch("[^\r\n]+") do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        
        if line:match("^SRCLEN") then
            data.srclen = tonumber(line:match("SRCLEN%s+([%d%.%-]+)")) or 1.0
            
        elseif line:match("^PPT") then
          
            local time_str, value_str, shape_str, tension_str = line:match("PPT%s+([%d%.%-]+)%s+([%d%.%-]+)%s+([%d%.%-]+)%s*([%d%.%-]*)")
            if time_str and value_str and shape_str then
                local time = tonumber(time_str)
                local value = tonumber(value_str)
                local shape = tonumber(shape_str) or 0
                local tension = tonumber(tension_str) or 0
                
                if time and value then
                    table.insert(data.points, {
                        time = time, 
                        value = value,
                        shape = shape,
                        tension = tension
                    })
                    data.point_count = data.point_count + 1
                    data.value_range.min = math.min(data.value_range.min, value)
                    data.value_range.max = math.max(data.value_range.max, value)
                end
            end
        end
    end

    if data.value_range.min == math.huge then data.value_range.min = 0 end
    if data.value_range.max == -math.huge then data.value_range.max = 1 end

    if data.value_range.min ~= math.huge and data.value_range.max ~= -math.huge then
        local min_val = data.value_range.min
        local max_val = data.value_range.max
        
        if min_val >= 0.0 and max_val <= 1.0 then
            data.source_envelope_type = "mute_or_normalized"
        elseif min_val >= -1.0 and max_val <= 1.0 then
            data.source_envelope_type = "pan_or_bipolar"
        elseif min_val >= 0.0 and max_val > 1.0 then
            data.source_envelope_type = "volume_or_gain"
        else
            data.source_envelope_type = "custom_range"
        end
    end
    
    return data
end

---------------------------------------------------
-- Preview functies
---------------------------------------------------

function GeneratePreview(item_data)
    if not item_data then
        return nil
    end
    
    if not item_data.points then
        return nil
    end
    
    if #item_data.points == 0 then
        return nil
    end
    
    local preview = {
        width = preview_width,
        height = preview_height,
        curve_points = {},
        control_points = {}
    }
 
    local pixel_points = {}
    for i, point in ipairs(item_data.points) do
        if not point then

            goto continue
        end
        
        if not point.time or not point.value then

            goto continue
        end
        
        local x = (point.time / item_data.srclen) * preview_width
        local normalized_value = point.value

        local envelope_type = item_data.source_envelope_type
        if not envelope_type or envelope_type == "unknown" then
   
            local max_val = 0
            for _, p in ipairs(item_data.points) do
                if p.value and p.value > max_val then max_val = p.value end
            end
            
            if max_val > 2.0 then
                envelope_type = "volume_or_gain"
            elseif point.value >= -1 and point.value <= 1 then
                envelope_type = "pan_or_bipolar"
            else
                envelope_type = "mute_or_normalized"
            end
        end
        
        if envelope_type == "pan_or_bipolar" then
            normalized_value = (point.value + 1.0) / 2.0
        else
            normalized_value = math.max(0.0, math.min(1.0, point.value))
        end
        
        local y = (1.0 - normalized_value) * preview_height
        
        local pixel_point = {
            x = x, 
            y = y, 
            value = point.value,
            shape = point.shape or 0,
            tension = point.tension or 0
        }
        
        table.insert(pixel_points, pixel_point) 
        table.insert(preview.control_points, {x = x, y = y})
        
        ::continue::
    end
    
    for i = 1, #pixel_points - 1 do
        local p1 = pixel_points[i]
        local p2 = pixel_points[i + 1]
        
        if not p1 or not p2 then

            goto continue_outer
        end
        
        if not p1.x or not p1.y or not p2.x or not p2.y then

            goto continue_outer
        end
        
        table.insert(preview.curve_points, {x = p1.x, y = p1.y})
        
        local segment_length = p2.x - p1.x
        if segment_length > 0 then
            local steps = math.max(3, math.floor(segment_length / 1.5)) 
            
            for step = 1, steps - 1 do
                local t = step / steps
                local curve_x = p1.x + (p2.x - p1.x) * t
                local curve_y = InterpolateValue(p1.value or 0, p2.value or 0, t, p1.shape or 0, p1.tension or 0)
                curve_y = (1.0 - curve_y) * preview_height
                
                table.insert(preview.curve_points, {x = curve_x, y = curve_y})
            end
        end
        
        ::continue_outer::
    end
    
    if #pixel_points > 0 then
        local last_point = pixel_points[#pixel_points]
        if last_point then
            table.insert(preview.curve_points, {x = last_point.x, y = last_point.y})
        end
    end
    
    return preview
end

function InterpolateValue(val1, val2, t, shape, tension)

    if shape == 0 then

        return val1 + (val2 - val1) * t
        
    elseif shape == 1 then

        return t >= 1.0 and val2 or val1
        
    elseif shape == 2 then

        local smooth_t = t * t * (3.0 - 2.0 * t)
        return val1 + (val2 - val1) * smooth_t
        
    elseif shape == 3 then

        local curve_t = t * t
        return val1 + (val2 - val1) * curve_t
        
    elseif shape == 4 then
    
        local curve_t = 1.0 - (1.0 - t) * (1.0 - t)
        return val1 + (val2 - val1) * curve_t
        
    elseif shape == 5 then

        local smooth_t = t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
        return val1 + (val2 - val1) * smooth_t
        
    elseif shape == 6 then
  
        local sine_t = (1.0 - math.cos(t * math.pi)) * 0.5
        return val1 + (val2 - val1) * sine_t
        
    else
        return val1 + (val2 - val1) * t
    end
end

function DrawPreview(preview, x, y)
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local colors = GetPreviewColors()
    
    if not preview then
        r.ImGui_DrawList_AddRect(draw_list, x, y, x + preview_width, y + preview_height, colors.border)
        r.ImGui_DrawList_AddText(draw_list, x + 10, y + 20, 0xAAAAAAFF, "No Preview")
        return
    end
    
    r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + preview_width, y + preview_height, colors.background)
    r.ImGui_DrawList_AddRect(draw_list, x, y, x + preview_width, y + preview_height, colors.border)
    
    if preview.curve_points and #preview.curve_points > 1 then
        for i = 1, #preview.curve_points - 1 do
            local p1 = preview.curve_points[i]
            local p2 = preview.curve_points[i + 1]
            
            if p1 and p2 and p1.x and p1.y and p2.x and p2.y then
                r.ImGui_DrawList_AddLine(draw_list, 
                    x + p1.x, y + p1.y,
                    x + p2.x, y + p2.y,
                    colors.curve, 1.5)
            end
        end
    end

    if not show_lines_only and preview.control_points then
        for i, point in ipairs(preview.control_points) do
            if point and point.x and point.y then
                r.ImGui_DrawList_AddCircleFilled(draw_list, x + point.x, y + point.y, 4, colors.points)
                r.ImGui_DrawList_AddCircle(draw_list, x + point.x, y + point.y, 4, 0x000000FF, 0, 1)
            end
        end
    end
end

---------------------------------------------------
-- Automation Item Insert functies
---------------------------------------------------

function InsertAutomationItemAtCursor(item_data)
    
    if not item_data then
        return false
    end

    local selected_env = r.GetSelectedEnvelope(0)
    if not selected_env then
        SetFooterMessage("Please select an envelope lane first")
        return false
    end

    local retval, env_name = r.GetEnvelopeName(selected_env)
    local cursor_pos = r.GetCursorPosition()

    local success = ApplyParsedDataAsEnvelopePoints(item_data, cursor_pos, false)
    
    if success then
        SetFooterMessage("Successfully applied: " .. (item_data.name or "Unknown"))
        return true
    else
        SetFooterMessage("Failed to apply automation data")
        return false
    end
end

---------------------------------------------------
-- Apply Parsed Data als Envelope Points
---------------------------------------------------

function ApplyParsedDataAsEnvelopePoints(item_data, target_position, replace_existing)
    if not item_data or not item_data.points or #item_data.points == 0 then
        SetFooterMessage("No valid automation data")
        return false
    end

    local env = ResolveTargetEnvelope()
    if not env then
        SetFooterMessage("Select an envelope lane first")
        return false
    end

    local env_info = GetEnvelopeInfo(env)
    local source_length = (item_data.srclen or 1.0) * 0.5

    local insert_start, insert_end, has_ts
    if target_position then
        insert_start = target_position
        insert_end = target_position + source_length
        has_ts = false
    else
        insert_start, insert_end, has_ts = GetEffectiveRange(source_length)
    end

    local target_length = insert_end - insert_start
    local time_scale = (has_ts and source_length > 0.001) and (target_length / source_length) or 1.0
    replace_existing = replace_existing or false

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    if replace_existing then
        for ptidx = r.CountEnvelopePoints(env) - 1, 0, -1 do
            local ok, time = r.GetEnvelopePointEx(env, -1, ptidx)
            if ok and time >= insert_start and time <= insert_end then
                r.DeleteEnvelopePointEx(env, -1, ptidx)
            end
        end
    end

    local points_added = 0
    for _, point in ipairs(item_data.points) do
        local corrected_time = point.time * 0.5
        local scaled_time = corrected_time * time_scale
        local absolute_time = insert_start + scaled_time

        local norm_value = NormalizeSourceValue(point.value, item_data.source_envelope_type)
        local final_value = ToEnvValue(norm_value, env_info.conv, env_info.lo, env_info.hi, env_info.mode)

        local ok = r.InsertEnvelopePoint(env, absolute_time, final_value, point.shape or 0, point.tension or 0, false, true)
        if ok then points_added = points_added + 1 end
    end

    r.Envelope_SortPoints(env)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    r.Undo_EndBlock("TK AIM: Apply envelope points (" .. points_added .. ")", -1)

    SetFooterMessage("Applied " .. points_added .. " envelope points" .. (has_ts and " (fitted to time selection)" or ""))
    return true
end

function TK_ConvertSelectedEnvelopePointsToAutomationItem(target_env)
    local env = target_env or r.GetSelectedEnvelope(0)
    if not env then return false end
    if r.CountEnvelopePoints(env) == 0 then return false end
    
    local position, endpos = math.huge, 0
    local has_selected_points = false
    
    for ptidx = 1, r.CountEnvelopePoints(env) do
        local retval, time, value, shape, tension, selected = r.GetEnvelopePointEx(env, -1, ptidx-1)
        if selected == true then 
            position = math.min(position, time)
            endpos = math.max(endpos, time)
            has_selected_points = true
        end
    end
    
    if has_selected_points and endpos - position > 0 and math.abs(endpos - position) > 0.01 then 
        r.InsertAutomationItem(env, -1, position, endpos - position)
        return true
    end
    return false
end

function ApplyAndCreateAutomationItem(item_data, target_env, target_time)
    if not item_data or not item_data.points or #item_data.points == 0 then
        SetFooterMessage("No valid automation data")
        return false
    end

    local env
    if target_env then
        env = target_env
    else
        env = ResolveTargetEnvelope()
    end
    if not env then
        SetFooterMessage("Select an envelope lane first")
        return false
    end

    local env_info = GetEnvelopeInfo(env)

    local max_time = 0
    for _, point in ipairs(item_data.points) do
        if point.time > max_time then max_time = point.time end
    end
    local source_length = max_time * 0.5

    local insert_start, insert_end, has_ts
    if target_time then
        insert_start = target_time
        if use_time_selection then
            local ts_s, ts_e = r.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
            if (ts_e - ts_s) >= 0.01 then
                insert_end = target_time + (ts_e - ts_s)
                has_ts = true
            else
                insert_end = target_time + source_length
                has_ts = false
            end
        else
            insert_end = target_time + source_length
            has_ts = false
        end
    else
        insert_start, insert_end, has_ts = GetEffectiveRange(source_length)
    end

    local target_length = insert_end - insert_start
    local time_scale = (has_ts and source_length > 0.001) and (target_length / source_length) or 1.0
    local final_length = has_ts and target_length or source_length

    local initial_automation_items = r.CountAutomationItems(env)

    local original_points = {}
    for ptidx = 0, r.CountEnvelopePoints(env) - 1 do
        local ok, time, value, shape, tension, selected = r.GetEnvelopePointEx(env, -1, ptidx)
        if ok and time >= insert_start and time <= insert_start + final_length then
            table.insert(original_points, {time = time, value = value, shape = shape, tension = tension})
        end
    end

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    for ptidx = r.CountEnvelopePoints(env) - 1, 0, -1 do
        local ok, time = r.GetEnvelopePointEx(env, -1, ptidx)
        if ok and time >= insert_start and time <= insert_start + final_length then
            r.DeleteEnvelopePointEx(env, -1, ptidx)
        end
    end

    local placed_count = 0
    for _, point in ipairs(item_data.points) do
        local corrected_time = point.time * 0.5
        local scaled_time = corrected_time * time_scale
        local absolute_time = insert_start + scaled_time

        local norm_value = NormalizeSourceValue(point.value, item_data.source_envelope_type)
        local final_value = ToEnvValue(norm_value, env_info.conv, env_info.lo, env_info.hi, env_info.mode)

        r.InsertEnvelopePoint(env, absolute_time, final_value, point.shape or 0, point.tension or 0, true, true)
        placed_count = placed_count + 1
    end

    r.Envelope_SortPoints(env)

    local conversion_success = TK_ConvertSelectedEnvelopePointsToAutomationItem(env)
    if not conversion_success then
        SetFooterMessage("Conversion failed (span too short)")
    end

    local automation_count_after = r.CountAutomationItems(env)

    if automation_count_after > initial_automation_items then
        local item_idx = automation_count_after - 1
        r.GetSetAutomationItemInfo(env, item_idx, "D_LENGTH", final_length, true)
        r.GetSetAutomationItemInfo(env, item_idx, "D_LOOPSRC", enable_loop and 1 or 0, true)
        r.GetSetAutomationItemInfo(env, item_idx, "D_PLAYRATE", 1.0, true)
    end

    for i = 0, r.CountAutomationItems(env) - 1 do
        r.GetSetAutomationItemInfo(env, i, "D_UISEL", 0, false)
    end

    for ptidx = r.CountEnvelopePoints(env) - 1, 0, -1 do
        local ok, time = r.GetEnvelopePointEx(env, -1, ptidx)
        if ok then
            if math.abs(time - insert_start) < 0.001 or math.abs(time - (insert_start + final_length)) < 0.001 then
                r.DeleteEnvelopePointEx(env, -1, ptidx)
            end
        end
    end

    for _, orig in ipairs(original_points) do
        local exists = false
        for ptidx = 0, r.CountEnvelopePoints(env) - 1 do
            local ok, time = r.GetEnvelopePointEx(env, -1, ptidx)
            if ok and math.abs(time - orig.time) < 0.001 then
                exists = true
                break
            end
        end
        if not exists then
            r.InsertEnvelopePoint(env, orig.time, orig.value, orig.shape, orig.tension, false, false)
        end
    end

    for ptidx = 0, r.CountEnvelopePoints(env) - 1 do
        local ok, time, value, shape, tension = r.GetEnvelopePointEx(env, -1, ptidx)
        if ok then
            r.SetEnvelopePointEx(env, -1, ptidx, time, value, shape, tension, false, false)
        end
    end

    r.Envelope_SortPoints(env)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    r.Undo_EndBlock("TK AIM: Create automation item", -1)

    if move_edit_cursor then r.SetEditCurPos(insert_start + final_length, true, false) end

    return true
end

---------------------------------------------------
-- Drag & Drop (requires SWS for context)
---------------------------------------------------
function HandleDragAndDrop()
    if not is_dragging or not drag_item then return end
    
    ValidateContext() -- Ensure context is valid before using ImGui functions
    
    if has_sws then
        r.BR_GetMouseCursorContext()
        local env = r.BR_GetMouseCursorContext_Envelope()
        local pos = r.BR_GetMouseCursorContext_Position and r.BR_GetMouseCursorContext_Position() or nil
        if env and pos then
            drag_hover_env = env
            drag_hover_pos = pos
            local ok, name = r.GetEnvelopeName(env)
            drag_hover_name = ok and name or nil
        end
    end
    if r.ImGui_IsMouseReleased(ctx, r.ImGui_MouseButton_Left()) then
        local placed = false
        if has_sws then
            r.BR_GetMouseCursorContext()
            local env = r.BR_GetMouseCursorContext_Envelope() or drag_hover_env
            local pos = (r.BR_GetMouseCursorContext_Position and r.BR_GetMouseCursorContext_Position()) or drag_hover_pos
            if env and pos then
                ApplyAndCreateAutomationItem(drag_item, env, pos)
                placed = true
            end
        end
        if not placed then
            if not has_sws then
                SetFooterMessage("Drag&Drop needs SWS extension installed")
            else
                SetFooterMessage("Drop on an envelope lane to place item")
            end
        end
        is_dragging = false
        drag_item = nil
        drag_hover_env = nil
        drag_hover_pos = nil
        drag_hover_name = nil
    end
end

function InsertActualAutomationItem(item_data)  
    if not item_data then

        return false
    end
    
    local selected_env = r.GetSelectedEnvelope(0)
    if not selected_env then
    SetFooterMessage("Please select an envelope lane first")
        return false
    end
    
    local cursor_pos = r.GetCursorPosition()
    local retval, env_name = r.GetEnvelopeName(selected_env)
        
    r.Undo_BeginBlock()
    
    local success = false

    if move_edit_cursor then r.SetEditCurPos(cursor_pos, true, false) end
  
    local ai_idx = r.InsertAutomationItem(selected_env, -1, cursor_pos, item_data.srclen or 1.0)
    if ai_idx >= 0 then
        success = true

    end
    
    if success then
        r.UpdateArrange()
        r.Undo_EndBlock("Insert automation item: " .. (item_data.name or "Unknown"), -1)
        SetFooterMessage("Basic automation item created; for full source data use 'Load as Envelope Points'")
        return true
    else
        r.Undo_EndBlock()
        SetFooterMessage("Automation item loading via API is limited; use 'Load as Envelope Points' or load from: " .. (item_data.path or ""))
        return false
    end
end

function ConvertSelectedEnvelopePointsToAutomationItem()
    local env = r.GetSelectedEnvelope(0)
    if not env then 
    SetFooterMessage("Please select an envelope first")
        return false
    end
    
    if r.CountEnvelopePoints(env) == 0 then 
    SetFooterMessage("No envelope points found")
        return false
    end
    
    local position, endpos = math.huge, 0
    local selected_count = 0
    
    for ptidx = 1, r.CountEnvelopePoints(env) do
        local retval, time, value, shape, tension, selected = r.GetEnvelopePointEx(env, -1, ptidx-1)
        if selected == true then 
            position = math.min(position, time)
            endpos = math.max(endpos, time)
            selected_count = selected_count + 1
        end
    end
    
    if selected_count == 0 then
        SetFooterMessage("Please select envelope points first")
        return false
    end
    
    if endpos - position > 0 and math.abs(endpos - position) > 0.1 then 
        r.InsertAutomationItem(env, -1, position, endpos - position)
        
        ScanAutomationItems()
        SetFooterMessage("Automation item created from " .. selected_count .. " envelope points")
        return true
    else
        SetFooterMessage("Selected points span is too small (< 0.1s)")
        return false
    end
end

---------------------------------------------------
-- Export envelope points to .ReaperAutoItem
---------------------------------------------------

function ExportEnvelopePointsToFile()
    local env = r.GetSelectedEnvelope(0)
    if not env then
        SetFooterMessage("Select an envelope first")
        return false
    end

    local point_count = r.CountEnvelopePoints(env)
    if point_count == 0 then
        SetFooterMessage("No envelope points found")
        return false
    end

    local env_info = GetEnvelopeInfo(env)

    local sel_start, sel_end = math.huge, -math.huge
    local has_selection = false
    local points = {}

    for i = 0, point_count - 1 do
        local ok, time, value, shape, tension, selected = r.GetEnvelopePointEx(env, -1, i)
        if ok then
            if selected then
                has_selection = true
                sel_start = math.min(sel_start, time)
                sel_end = math.max(sel_end, time)
            end
            table.insert(points, {time = time, value = value, shape = shape, tension = tension, selected = selected})
        end
    end

    local export_points = {}
    local time_offset = 0

    if has_selection and sel_end > sel_start then
        time_offset = sel_start
        for _, p in ipairs(points) do
            if p.selected then
                local norm_value = FromEnvValue(p.value, env_info.conv, env_info.lo, env_info.hi, env_info.mode)
                table.insert(export_points, {
                    time = (p.time - time_offset) * 2,
                    value = norm_value,
                    shape = p.shape,
                    tension = p.tension
                })
            end
        end
    else
        local ts_s, ts_e = r.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
        local use_ts = (ts_e - ts_s) >= 0.01
        if use_ts then
            time_offset = ts_s
            for _, p in ipairs(points) do
                if p.time >= ts_s and p.time <= ts_e then
                    local norm_value = FromEnvValue(p.value, env_info.conv, env_info.lo, env_info.hi, env_info.mode)
                    table.insert(export_points, {
                        time = (p.time - time_offset) * 2,
                        value = norm_value,
                        shape = p.shape,
                        tension = p.tension
                    })
                end
            end
        else
            if #points > 0 then time_offset = points[1].time end
            for _, p in ipairs(points) do
                local norm_value = FromEnvValue(p.value, env_info.conv, env_info.lo, env_info.hi, env_info.mode)
                table.insert(export_points, {
                    time = (p.time - time_offset) * 2,
                    value = norm_value,
                    shape = p.shape,
                    tension = p.tension
                })
            end
        end
    end

    if #export_points == 0 then
        SetFooterMessage("No points to export")
        return false
    end

    if not EnsureAutomationFolderExists() then return false end

    local total_time = export_points[#export_points].time

    local retval, name = r.GetUserInputs("Export as .ReaperAutoItem", 1, "Name:", "Exported_" .. os.date("%Y%m%d_%H%M%S"))
    if not retval or not name or name == "" then return false end

    local filename = name .. ".ReaperAutoItem"
    local filepath = automation_folder .. dir_sep .. filename

    local file_check = io.open(filepath, "r")
    if file_check then
        file_check:close()
        local overwrite = r.ShowMessageBox("File already exists:\n" .. filename .. "\n\nOverwrite?", script_name, 4)
        if overwrite ~= 6 then return false end
    end

    local file = io.open(filepath, "w")
    if not file then
        SetFooterMessage("Could not create file: " .. filepath)
        return false
    end

    file:write("SRCLEN " .. string.format("%.10f", total_time) .. "\n")
    for _, p in ipairs(export_points) do
        file:write(string.format("PPT %.10f %.10f %d %.10f\n", p.time, p.value, p.shape, p.tension))
    end
    file:close()

    ScanAutomationItems()
    SetFooterMessage("Exported: " .. filename .. " (" .. #export_points .. " points)")
    return true
end

---------------------------------------------------
-- ReaCurve MORPH bridge (selected envelope points)
---------------------------------------------------

local morph_cleanup = nil

function MorphCleanupPoll()
    if not morph_cleanup then return end
    local env = morph_cleanup.env
    if not r.ValidatePtr(env, "TrackEnvelope*") then
        morph_cleanup = nil
        return
    end

    morph_cleanup.frames = morph_cleanup.frames + 1

    local any_found = false
    for _, t in ipairs(morph_cleanup.times) do
        for ptidx = 0, r.CountEnvelopePoints(env) - 1 do
            local ok, time, value, shape, tension, selected = r.GetEnvelopePointEx(env, -1, ptidx)
            if ok and math.abs(time - t) < 0.0001 then
                any_found = true
                if not selected then
                    r.SetEnvelopePointEx(env, -1, ptidx, time, value, shape, tension, true, true)
                end
                break
            end
        end
    end

    if any_found and morph_cleanup.frames <= 100 then
        r.defer(MorphCleanupPoll)
        return
    end

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    for i = #morph_cleanup.times, 1, -1 do
        local target_t = morph_cleanup.times[i]
        for ptidx = r.CountEnvelopePoints(env) - 1, 0, -1 do
            local ok, time = r.GetEnvelopePointEx(env, -1, ptidx)
            if ok and math.abs(time - target_t) < 0.0001 then
                r.DeleteEnvelopePointEx(env, -1, ptidx)
                break
            end
        end
    end
    r.Envelope_SortPoints(env)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    r.Undo_EndBlock("TK AIM: MORPH cleanup", -1)

    if morph_cleanup.frames > 100 then
        SetFooterMessage("MORPH timeout — points removed. Click Capture in ReaCurve first!")
    else
        SetFooterMessage("MORPH capture complete — temporary points removed")
    end
    morph_cleanup = nil
end

function SendToMorphSlot(item_data, slot)
    if not item_data or not item_data.points or #item_data.points == 0 then
        SetFooterMessage("No valid data for MORPH slot")
        return false
    end

    local env = ResolveTargetEnvelope()
    if not env then
        SetFooterMessage("Select an envelope lane for MORPH")
        return false
    end

    local env_info = GetEnvelopeInfo(env)
    local source_length = (item_data.srclen or 1.0) * 0.5
    local insert_start = r.GetCursorPosition()

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    for ptidx = 0, r.CountEnvelopePoints(env) - 1 do
        local ok, time, value, shape, tension = r.GetEnvelopePointEx(env, -1, ptidx)
        if ok then
            r.SetEnvelopePointEx(env, -1, ptidx, time, value, shape, tension, false, false)
        end
    end

    local inserted_times = {}
    local points_added = 0
    for _, point in ipairs(item_data.points) do
        local corrected_time = point.time * 0.5
        local absolute_time = insert_start + corrected_time
        local norm_value = NormalizeSourceValue(point.value, item_data.source_envelope_type)
        local final_value = ToEnvValue(norm_value, env_info.conv, env_info.lo, env_info.hi, env_info.mode)

        local ok = r.InsertEnvelopePoint(env, absolute_time, final_value, point.shape or 0, point.tension or 0, true, true)
        if ok then
            points_added = points_added + 1
            table.insert(inserted_times, absolute_time)
        end
    end

    r.Envelope_SortPoints(env)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    r.Undo_EndBlock("TK AIM: MORPH prep (" .. points_added .. " pts)", -1)

    morph_cleanup = { env = env, times = inserted_times, frames = 0 }
    r.defer(MorphCleanupPoll)

    SetFooterMessage("MORPH " .. slot .. ": " .. points_added .. " points — waiting for ReaCurve capture...")
    return true
end

---------------------------------------------------
-- Select for SCULPT helper
---------------------------------------------------

function SelectInsertedPoints(env, start_time, end_time)
    if not env then return end
    for ptidx = 0, r.CountEnvelopePoints(env) - 1 do
        local ok, time, value, shape, tension, selected = r.GetEnvelopePointEx(env, -1, ptidx)
        if ok and time >= start_time - 0.001 and time <= end_time + 0.001 then
            r.SetEnvelopePointEx(env, -1, ptidx, time, value, shape, tension, true, false)
        end
    end
    r.Envelope_SortPoints(env)
    r.UpdateArrange()
end

---------------------------------------------------
-- GUI functies
---------------------------------------------------

function DrawMainWindow()
    ValidateContext() -- Ensure context is valid before using it
    
    local window_flags = r.ImGui_WindowFlags_NoScrollbar() + r.ImGui_WindowFlags_NoScrollWithMouse()
    r.ImGui_SetNextWindowSize(ctx, 800, 600, r.ImGui_Cond_FirstUseEver())
    
    -- Push styles voor het window
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBg(), 0x000000FF)          
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgActive(), 0x000000FF)   
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgCollapsed(), 0x000000FF) 
    
    local visible, open = r.ImGui_Begin(ctx, script_name, true, window_flags)
    
    if visible then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x444444FF)      
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x555555FF)  
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x333333FF)  
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 8.0)
        
        r.ImGui_Text(ctx, "Automation Items: " .. #automation_items)
        
        r.ImGui_PopStyleVar(ctx, 1)
        r.ImGui_PopStyleColor(ctx, 3)
        
        r.ImGui_SameLine(ctx)
        local content_width = r.ImGui_GetContentRegionAvail(ctx)
        local settings_button_width = 30
        r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + content_width - settings_button_width)
        
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000000)        
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x77777744) 
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x55555588)  
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 8.0)
        
        if r.ImGui_Button(ctx, "⚙", settings_button_width, 0) then
            r.ImGui_OpenPopup(ctx, "settings_menu")
        end
        Tooltip("Open settings")
        
        r.ImGui_PopStyleVar(ctx, 1)
        r.ImGui_PopStyleColor(ctx, 3)
        
        if r.ImGui_BeginPopup(ctx, "settings_menu") then
            local changed, new_value = r.ImGui_Checkbox(ctx, "🔄 Enable Loop", enable_loop)
            Tooltip("Loop automation items when inserted")
            if changed then
                enable_loop = new_value
                SaveSettings()
            end
            
            local mec_changed, mec_value = r.ImGui_Checkbox(ctx, "▶ Move Edit Cursor", move_edit_cursor)
            Tooltip("Move edit cursor to end of inserted item")
            if mec_changed then
                move_edit_cursor = mec_value
                SaveSettings()
            end
            
            local slo_changed, slo_value = r.ImGui_Checkbox(ctx, "Lines Only", show_lines_only)
            Tooltip("Hide control point dots in previews")
            if slo_changed then
                show_lines_only = slo_value
                SaveSettings()
            end

            local ts_changed, ts_value = r.ImGui_Checkbox(ctx, "⏱ Use Time Selection", use_time_selection)
            Tooltip("Scale items to fit the current time selection")
            if ts_changed then
                use_time_selection = ts_value
                SaveSettings()
            end

            local tt_changed, tt_value = r.ImGui_Checkbox(ctx, "💬 Show Tooltips", show_tooltips)
            Tooltip("Show helpful tooltips on hover")
            if tt_changed then
                show_tooltips = tt_value
                SaveSettings()
            end
            if r.ImGui_ColorButton(ctx, "##curve_color_btn", curve_color, 0, 20, 20) then
                r.ImGui_OpenPopup(ctx, "curve_color_picker")
            end
            Tooltip("Preview line color")
            r.ImGui_SameLine(ctx)
            r.ImGui_Text(ctx, "Line")
            if r.ImGui_BeginPopup(ctx, "curve_color_picker") then
                local ok, col = r.ImGui_ColorPicker4(ctx, "##curve_picker", curve_color, r.ImGui_ColorEditFlags_NoSidePreview())
                if ok then
                    curve_color = col
                    SaveSettings()
                end
                r.ImGui_EndPopup(ctx)
            end
            r.ImGui_Spacing(ctx)
            if r.ImGui_ColorButton(ctx, "##points_color_btn", points_color, 0, 20, 20) then
                r.ImGui_OpenPopup(ctx, "points_color_picker")
            end
            Tooltip("Preview dot color")
            r.ImGui_SameLine(ctx)
            r.ImGui_Text(ctx, "Dots")
            if r.ImGui_BeginPopup(ctx, "points_color_picker") then
                local ok2, col2 = r.ImGui_ColorPicker4(ctx, "##points_picker", points_color, r.ImGui_ColorEditFlags_NoSidePreview())
                if ok2 then
                    points_color = col2
                    SaveSettings()
                end
                r.ImGui_EndPopup(ctx)
            end
            r.ImGui_Separator(ctx)
            if r.ImGui_MenuItem(ctx, "ℹ️ About") then
                SetFooterMessage("TK Automation Item Manager v0.1.0 — ReaCurve Integration")
            end
            
            r.ImGui_EndPopup(ctx)
        end
        
        r.ImGui_Separator(ctx)

        if r.ImGui_BeginChild(ctx, "ItemsScroll", 0, -FOOTER_H) then
            if #automation_items > 0 then
                DrawItemsGrid()
            else
                r.ImGui_TextWrapped(ctx, "No automation items found.")
                r.ImGui_TextWrapped(ctx, "Create some automation items in REAPER first, then click Refresh.")
            end
            r.ImGui_EndChild(ctx)
        end

        DrawStatusBar()
        
        r.ImGui_End(ctx)
    end
    
    -- Pop de window styles - dit moet altijd gebeuren, ongeacht visible state
    r.ImGui_PopStyleColor(ctx, 3)  
    
    return open
end

function DrawItemsGrid()
    if not automation_items or #automation_items == 0 then
        r.ImGui_Text(ctx, "No automation items loaded")
        return
    end
    
    local cols = math.floor(r.ImGui_GetContentRegionAvail(ctx) / (preview_width + 8))
    cols = math.max(1, cols)
    
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_CellPadding(), 4, 4)  
    
    local table_flags = r.ImGui_TableFlags_None()
    if r.ImGui_BeginTable(ctx, "automation_items", cols, table_flags) then
        for i, item in ipairs(automation_items) do
            if not item then

                goto continue_item
            end
            
            r.ImGui_TableNextColumn(ctx)

            local cursor_x, cursor_y = r.ImGui_GetCursorScreenPos(ctx)

            DrawPreview(item.preview, cursor_x, cursor_y)
            

            r.ImGui_SetCursorScreenPos(ctx, cursor_x, cursor_y)
            if r.ImGui_InvisibleButton(ctx, "item_" .. i, preview_width, preview_height) then
                ApplyAndCreateAutomationItem(item)
            end
            if r.ImGui_IsItemActive(ctx) and r.ImGui_IsMouseDragging(ctx, r.ImGui_MouseButton_Left(), 5.0) then
                is_dragging = true
                drag_item = item
            end
            
            if r.ImGui_IsItemClicked(ctx, r.ImGui_MouseButton_Right()) then
                r.ImGui_OpenPopup(ctx, "context_menu_" .. i)
            end
            
            if r.ImGui_BeginPopup(ctx, "context_menu_" .. i) then
                if r.ImGui_MenuItem(ctx, "📌 Insert as Points") then
                    ApplyParsedDataAsEnvelopePoints(item, nil, false)
                end
                Tooltip("Insert curve as envelope points on the selected envelope")

                r.ImGui_Separator(ctx)

                if r.ImGui_MenuItem(ctx, "🔀 MORPH Slot A") then
                    SendToMorphSlot(item, "A")
                end
                Tooltip("Send to ReaCurve MORPH Slot A for morphing")

                if r.ImGui_MenuItem(ctx, "🔀 MORPH Slot B") then
                    SendToMorphSlot(item, "B")
                end
                Tooltip("Send to ReaCurve MORPH Slot B for morphing")

                r.ImGui_Separator(ctx)

                if r.ImGui_MenuItem(ctx, "🗑️ Delete") then
                    DeleteAutomationItem(item, i)
                end
                Tooltip("Delete this automation item file from disk")

                if r.ImGui_MenuItem(ctx, "✏️ Rename") then
                    RenameAutomationItem(item, i)
                end
                Tooltip("Rename this automation item file")

                r.ImGui_Separator(ctx)

                if r.ImGui_MenuItem(ctx, "📁 Show in Explorer") then
                    ShowItemInExplorer(item)
                end
                Tooltip("Open folder containing this file in Explorer")

                if r.ImGui_MenuItem(ctx, "📋 Copy Path") then
                    CopyItemPath(item)
                end
                Tooltip("Copy the full file path to clipboard")

                r.ImGui_EndPopup(ctx)
            end

            if r.ImGui_IsItemHovered(ctx) and show_tooltips then
                r.ImGui_BeginTooltip(ctx)
                r.ImGui_Text(ctx, item.name or "Unknown")
                r.ImGui_Text(ctx, "Click: insert as automation item")
                r.ImGui_Text(ctx, "Drag: drop on envelope in Arrange")
                r.ImGui_Text(ctx, "Right-click: more options")

                local corrected_srclen = (item.srclen or 0) * 0.5
                r.ImGui_Text(ctx, "📊 " .. (item.point_count or 0) .. " points, " .. string.format("%.1fs", corrected_srclen))
                r.ImGui_EndTooltip(ctx)
            end
            
            if is_dragging and drag_item == item then
                r.ImGui_BeginTooltip(ctx)
                r.ImGui_Text(ctx, "Drop on an envelope lane in Arrange")
                r.ImGui_EndTooltip(ctx)
            end

            r.ImGui_Text(ctx, item.name or "Unknown")
            
            if item.display_folder then
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x808080FF)
                r.ImGui_Text(ctx, item.display_folder)
                r.ImGui_PopStyleColor(ctx)
            end
            
            local srclen = item.srclen or 0
            local point_count = item.point_count or 0 
            local corrected_srclen = srclen * 0.5
            r.ImGui_Text(ctx, string.format("%.1fs, %d pts", corrected_srclen, point_count))
            
            ::continue_item::
        end
        
        r.ImGui_EndTable(ctx)
        r.ImGui_PopStyleVar(ctx, 1)  
    end
end

---------------------------------------------------
-- Context Menu functies
---------------------------------------------------

function DeleteAutomationItem(item, index)
    if not item or not item.path then
        SetFooterMessage("Cannot delete: invalid item data")
        return
    end
    local ok, err = os.remove(item.path)
    if ok then
        table.remove(automation_items, index)
        SaveCache()
        SetFooterMessage("Deleted: " .. (item.filename or ""))
    else
        SetFooterMessage("Failed to delete: " .. (item.path or ""))
    end
end

function ShowItemInExplorer(item)
    if not item or not item.path then
    SetFooterMessage("Cannot show: invalid item path")
        return
    end
    local osn = r.GetOS()
    if osn:match('^Win') then
        os.execute('explorer /select,"' .. item.path .. '"')
    elseif osn:match('^OSX') then
        os.execute('open -R "' .. item.path .. '"')
    else
        local dir = dirname(item.path)
        if dir == '' then dir = '.' end
        os.execute('xdg-open "' .. dir .. '"')
    end
end

function CopyItemPath(item)
    if not item or not item.path then
        SetFooterMessage("Cannot copy: invalid item path")
        return
    end
    r.ImGui_SetClipboardText(ctx, item.path)
    SetFooterMessage("Path copied to clipboard")
end

function RenameAutomationItem(item, index)
    if not item or not item.path then
    SetFooterMessage("Cannot rename: invalid item data")
        return
    end
    
    local old_filename = item.filename or "Unknown"
    local old_name = old_filename:gsub("%.ReaperAutoItem$", "")
    local retval, new_name = r.GetUserInputs("Rename Automation Item", 1, "New name:", old_name)
    
    if retval and new_name and new_name ~= "" and new_name ~= old_name then
        local new_filename = new_name .. ".ReaperAutoItem"
        local folder_path = item.path:match("^(.+[/\\])")
        local new_path = folder_path .. new_filename

        local file = io.open(new_path, "r")
        if file then
            file:close()
            SetFooterMessage("File already exists: " .. new_filename)
            return
        end
        
        local ok, err = os.rename(item.path, new_path)
        if ok then
            automation_items[index].name = new_name
            automation_items[index].filename = new_filename
            automation_items[index].path = new_path
            table.sort(automation_items, function(a, b)
                local folder_a = (a.display_folder or "Home"):lower()
                local folder_b = (b.display_folder or "Home"):lower()
                if folder_a ~= folder_b then
                    if folder_a == "home" then return true end
                    if folder_b == "home" then return false end
                    return folder_a < folder_b
                end
                local name_a = (a.name or ""):lower()
                local name_b = (b.name or ""):lower()
                return name_a < name_b
            end)
            SaveCache()
            SetFooterMessage("Successfully renamed to: " .. new_filename)
        else
            SetFooterMessage("Failed to rename file: " .. old_filename)
        end
    end
end

---------------------------------------------------
-- Color Scheme functies
---------------------------------------------------

function GetPreviewColors()
    local bg, br
    if color_scheme == "blue_white" then
        bg, br = 0x1A1A2EFF, 0x4DAFB2FF
    elseif color_scheme == "pure_white" then
        bg, br = 0x111111FF, 0x888888FF
    else
        bg, br = 0x222222FF, 0x666666FF
    end
    return {
        curve = curve_color,
        points = points_color,
        background = bg,
        border = br
    }
end

function DrawStatusBar()
    if not r.ImGui_BeginChild(ctx, "Footer", -1, FOOTER_H) then return end
    r.ImGui_Separator(ctx)
    if r.ImGui_BeginChild(ctx, "FooterInfo", -1, INFO_H) then
        local env = r.GetSelectedEnvelope(0)
        if env then
            local retval, env_name = r.GetEnvelopeName(env)
            local env_type = GetEnvelopeType(env)
            r.ImGui_Text(ctx, "Selected envelope: " .. (env_name or "Unknown"))
            r.ImGui_SameLine(ctx)
            if env_type == "volume" then
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFF4400FF)
                r.ImGui_Text(ctx, "⚠️ [Volume]")
                r.ImGui_PopStyleColor(ctx)
            else
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x00FF00FF)
                r.ImGui_Text(ctx, "✓ [" .. (env_type or "unknown") .. " - OK]")
                r.ImGui_PopStyleColor(ctx)
            end
        else
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x888888FF)
            r.ImGui_Text(ctx, "No envelope selected - Select envelope lane first")
            r.ImGui_PopStyleColor(ctx)
        end
        if footer_message ~= "" and r.time_precise() - footer_message_time < footer_message_duration then
            r.ImGui_Spacing(ctx)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x00AAFFFF)
            r.ImGui_TextWrapped(ctx, "ℹ️ " .. footer_message)
            r.ImGui_PopStyleColor(ctx)
        end
        r.ImGui_EndChild(ctx)
    end
    r.ImGui_Separator(ctx)
    
    local available_width = r.ImGui_GetContentRegionAvail(ctx)
    
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x444444FF)      
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x555555FF)  
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x333333FF)   
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(),2.0)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 1, 1)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 2, 2)
    
    local spacing_x = 4
    local top_cols = 5
    local top_btn_w = math.max(50, math.floor((available_width - spacing_x) / top_cols))

    if r.ImGui_Button(ctx, "Refresh", top_btn_w, 0) then
        ScanAutomationItems()
        SetFooterMessage("Refreshed! " .. #automation_items .. " items found")
    end
    Tooltip("Rescan AutomationItems folder")

    r.ImGui_SameLine(ctx)

    if r.ImGui_Button(ctx, "Convert", top_btn_w, 0) then
        local success = ConvertSelectedEnvelopePointsToAutomationItem()
        if not success then
            SetFooterMessage("Conversion failed — check envelope selection and points")
        end
    end
    Tooltip("Convert selected envelope points to automation item")

    r.ImGui_SameLine(ctx)

    if r.ImGui_Button(ctx, "Save", top_btn_w, 0) then
        r.Main_OnCommand(42092, 0)
        SetFooterMessage("Save automation item command executed")
    end
    Tooltip("Save selected automation item to file")

    r.ImGui_SameLine(ctx)

    if r.ImGui_Button(ctx, "Export", top_btn_w, 0) then
        ExportEnvelopePointsToFile()
    end
    Tooltip("Export envelope points to .ReaperAutoItem file")

    r.ImGui_SameLine(ctx)

    if r.ImGui_Button(ctx, "Folder", top_btn_w, 0) then
        if EnsureAutomationFolderExists() then
            OpenPathInExplorer(automation_folder)
        end
    end
    Tooltip("Open AutomationItems folder in Explorer")

    local bottom_col_w = math.max(80, math.floor((available_width - spacing_x) / 2))

    if r.ImGui_Button(ctx, "Insert New", bottom_col_w, 0) then
        r.Main_OnCommand(42082, 0)
        SetFooterMessage("Inserted automation item")
    end
    Tooltip("Insert a new empty automation item on selected envelope")
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Edge points", bottom_col_w, 0) then
        r.Main_OnCommand(42209, 0)
        SetFooterMessage("Added edge points")
    end
    Tooltip("Add edge points at automation item boundaries")
    
    if r.ImGui_Button(ctx, "Pool (duplicate)", bottom_col_w, 0) then
        r.Main_OnCommand(42085, 0)
        SetFooterMessage("Pooled duplicate created")
    end
    Tooltip("Duplicate selected automation item as pooled copy")
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Unpool (sel)", bottom_col_w, 0) then
        r.Main_OnCommand(42084, 0)
        SetFooterMessage("Unpooled selected item(s)")
    end
    Tooltip("Make selected automation item independent (unpool)")
    
    r.ImGui_PopStyleVar(ctx, 3)
    r.ImGui_PopStyleColor(ctx, 3)
    r.ImGui_EndChild(ctx)
end

---------------------------------------------------
-- Main
---------------------------------------------------

function Main()
    local open = DrawMainWindow()
    HandleDragAndDrop()
    
    if open then
        r.defer(Main)
    end
end
LoadSettings()

if not json_ok then
    footer_message = "json_aim.lua not found — cache disabled; scanning filesystem each time"
    footer_message_time = r.time_precise()
end

automation_folder_exists = AutomationFolderExists()

if not LoadCache() then
    if automation_folder_exists then
        ScanAutomationItems()
    else
        SetFooterMessage("AutomationItems folder not found at: " .. automation_folder .. " — save an automation item first or create this folder")
    end
end

-- Cleanup function for when script exits
function cleanup()
    ctx = nil
end

r.atexit(cleanup)

Main()
