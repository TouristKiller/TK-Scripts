-- @description TK Automation Item Manager (AIM)
-- @version 0.0.7
-- @author TouristKiller
-- @about
--   Automation Item Manager with visual previews
-- @changelog:
--   Attempt to make cross platform (Windows/Linux/Mac) by avoiding OS-specific commands (need user feedback on this)
--   Added insert Automation Item at cursor position (time selection)
--   Added insert end points (if not present) to avoid issues with some envelopes
--   Made move edit cursor optional
--   Added Drag&Drop (testing needed!!)
--   Added color pickers for curve and points
--   Added buttons for pool and unpool
--   Added some extra checks and messages

-- THANX TO MPL FOR ALL THE THINGS HE DOES FOR THE REAPER COMMUNITY!! (I Used code inspired by MPL to do the conversions)
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
    -- Voor ReaImGui is het beter om geen context te destroyen
    -- We checken alleen of de pointer nog geldig is
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
local FOOTER_H = 120  
local INFO_H = 45     

local enable_loop = false
local color_scheme = "green_yellow"  
local show_lines_only = false  
local move_edit_cursor = false

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
        
        local settings = json.decode(content)
        if settings and type(settings) == "table" then
            enable_loop = settings.enable_loop or false
            color_scheme = settings.color_scheme or "green_yellow"
            show_lines_only = settings.show_lines_only or false
            move_edit_cursor = settings.move_edit_cursor or false
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

function ConvertValueForEnvelope(value, env_type)
    if env_type == "volume" then
        if value <= 0.001 then
            volume_value = 0.0
        elseif value <= 0.5 then
            local t = (value - 0.001) / (0.5 - 0.001)
            volume_value = 0.001 + (t * 424.999) 
        else
            local t = (value - 0.5) / 0.5
            volume_value = 425.0 + (t * 425.0)  
        end
        return volume_value
    elseif env_type == "pan" then
        return (value * 2.0) - 1.0
    elseif env_type == "pitch" then
        if math.abs(value) > 12 then
            return (value + 1200) / 2400
        else
            return value
        end
    elseif env_type == "mute" then
        return value > 0.5 and 1 or 0
    else
        return value
    end
end

---------------------------------------------------
-- Volume envelope handling
---------------------------------------------------

function IsVolumeEnvelope(envelope)
    if not envelope then return false end
    
    local retval, env_name = r.GetEnvelopeName(envelope)
    if not retval then return false end
    
    local lower_name = env_name:lower()
    return lower_name:match("volume") or lower_name:match("vol") or lower_name:match("track volume")
end

function LoadCache()
    if not json_ok then return false end
    local file = io.open(cache_file, "r")
    if file then
        local content = file:read("*all")
        file:close()
        
        local cached_items = json.decode(content)
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
    local ret = r.ShowMessageBox("AutomationItems folder not found:\n" .. automation_folder .. "\n\nWil je deze nu aanmaken?", script_name, 4)
    if ret == 6 then -- Yes
        local ok = r.RecursiveCreateDirectory and (r.RecursiveCreateDirectory(automation_folder, 0) == 1)
        if ok then
            automation_folder_exists = true
            SetFooterMessage("AutomationItems folder aangemaakt")
            return true
        else
            SetFooterMessage("Kon AutomationItems folder niet aanmaken")
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
-- NIEUWE functie: Apply Parsed Data als Envelope Points
---------------------------------------------------

function ApplyParsedDataAsEnvelopePoints(item_data, target_position, replace_existing)
    
    if not item_data or not item_data.points or #item_data.points == 0 then
    SetFooterMessage("No valid automation data to apply")
        return false
    end
    
    local env = r.GetSelectedEnvelope(0)
    if not env then
    SetFooterMessage("Please select an envelope first")
        return false
    end
    
    local retval, env_name = r.GetEnvelopeName(env)


    local target_envelope_type = "unknown"
    local source_envelope_type = item_data.source_envelope_type or "unknown"

    if env_name then
        local lower_name = env_name:lower()
        if lower_name:match("volume") or lower_name:match("vol") then
            target_envelope_type = "volume"
        elseif lower_name:match("mute") then
            target_envelope_type = "mute" 
        elseif lower_name:match("pan") then
            target_envelope_type = "pan"
        end
    end
    
    local needs_conversion = false
    local conversion_info = ""
    
    if source_envelope_type == "mute_or_normalized" and target_envelope_type == "volume" then
        needs_conversion = true
        conversion_info = "Converting MUTE/normalized (0-1) to VOLUME scaling"
    elseif source_envelope_type == "volume_or_gain" and target_envelope_type == "mute" then
        needs_conversion = true  
        conversion_info = "Converting VOLUME to MUTE (clamping to 0-1)"
    elseif source_envelope_type == "pan_or_bipolar" and target_envelope_type ~= "pan" then
        needs_conversion = true
        conversion_info = "Converting PAN (-1 to +1) to " .. target_envelope_type .. " range"
    end
    
    if needs_conversion then

    else

    end

    local is_volume_env = false
    local envelope_info = ""
    
    if target_envelope_type == "volume" then

        if r.BR_EnvAlloc then
            local br_env = r.BR_EnvAlloc(env, false)
            if br_env then
                local active, visible, armed, inLane, laneHeight, defaultShape, minValue, maxValue, centerValue, type, faderScaling = r.BR_EnvGetProperties(br_env)
                r.BR_EnvFree(br_env, true)
                
                is_volume_env = faderScaling or false
                envelope_info = string.format("min=%.3f max=%.3f center=%.3f fader=%s", 
                                            minValue or 0, maxValue or 1, centerValue or 0.5, tostring(faderScaling))

            end
        else

            is_volume_env = true 
        end
    end
    
    target_position = target_position or r.GetCursorPosition()
    replace_existing = replace_existing or false
    
    r.Undo_BeginBlock()
    
    if replace_existing then
        local start_time = target_position
        local end_time = target_position + item_data.srclen
        
        for ptidx = r.CountEnvelopePoints(env) - 1, 0, -1 do
            local retval, time, value, shape, tension, selected = r.GetEnvelopePointEx(env, -1, ptidx)
            if time >= start_time and time <= end_time then
                r.DeleteEnvelopePoint(env, ptidx)
            end
        end
    end
    
    local points_added = 0
    for i, point in ipairs(item_data.points) do

        local corrected_time = point.time * 0.5 
        local absolute_time = target_position + corrected_time

        local scaled_value = point.value

        if target_envelope_type == "volume" then
            
            if source_envelope_type == "mute_or_normalized" then
                if point.value <= 0.0 then
                    scaled_value = 0.0  
                elseif point.value >= 1.0 then
                    scaled_value = 1.0  
                else
                    scaled_value = point.value
                end
                
            elseif source_envelope_type == "pan_or_bipolar" then
                scaled_value = math.abs(point.value)  
                
            elseif source_envelope_type == "volume_or_gain" then
                scaled_value = point.value
                
            else
             
                if point.value >= -1.0 and point.value <= 1.0 then
                  
                    scaled_value = math.abs(point.value)
                else
                    scaled_value = point.value
                end
            end
            
        elseif source_envelope_type == "volume_or_gain" and target_envelope_type == "mute" then
          
            scaled_value = math.max(0.0, math.min(1.0, point.value))
            
        elseif source_envelope_type == "pan_or_bipolar" and target_envelope_type == "mute" then
            scaled_value = math.abs(point.value)
            
        elseif target_envelope_type == "pan" then

            scaled_value = point.value
            
        else
            scaled_value = point.value
        end
        
        local point_index = r.InsertEnvelopePoint(
            env,                    -- envelope
            absolute_time,          -- time position
            scaled_value,          -- scaled value
            point.shape or 0,      -- shape
            point.tension or 0,    -- tension
            false,                 -- selected
            true                   -- noSort (we voegen chronologisch toe)
        )
        
        if (type(point_index) == "number" and point_index >= 0) or (type(point_index) == "boolean" and point_index == true) then
            points_added = points_added + 1
        end
    end
    
    r.Envelope_SortPoints(env)
    
    r.UpdateArrange()
    r.Undo_EndBlock("Apply parsed automation as envelope points (" .. points_added .. " points)", -1)
    
    SetFooterMessage("Applied " .. points_added .. " envelope points from parsed data")
    
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
    SetFooterMessage("No valid automation data found")
        return false
    end
    
    local env = target_env or r.GetSelectedEnvelope(0)
    if not env then
    SetFooterMessage("Please select an envelope lane first")
        return false
    end
    
    local cursor_pos = (target_time ~= nil) and target_time or r.GetCursorPosition()
    local max_time = 0
    for i, point in ipairs(item_data.points) do
        if point.time > max_time then
            max_time = point.time
        end
    end

    local corrected_length = max_time * 0.5  
    local first_time = cursor_pos
    local last_time = cursor_pos + corrected_length
    local env_type = GetEnvelopeType(env)

    local retval, env_name = r.GetEnvelopeName(env)
    local initial_points = r.CountEnvelopePoints(env)
    local initial_automation_items = r.CountAutomationItems(env)
    
   
    local original_points = {}
    local points_in_selection = 0
    
    for ptidx = 0, r.CountEnvelopePoints(env) - 1 do
        local retval, time, value, shape, tension, selected = r.GetEnvelopePointEx(env, -1, ptidx)
        if retval and time >= first_time and time <= last_time then
            table.insert(original_points, {
                time = time,
                value = value,
                shape = shape,
                tension = tension
            })
            points_in_selection = points_in_selection + 1
        end
    end

    
    r.Undo_BeginBlock()
    
    local deleted_count = 0
    for ptidx = r.CountEnvelopePoints(env) - 1, 0, -1 do
        local retval, time, value, shape, tension, selected = r.GetEnvelopePointEx(env, -1, ptidx)
        if retval and time >= first_time and time <= last_time then
            r.DeleteEnvelopePointEx(env, -1, ptidx)  
            deleted_count = deleted_count + 1
        end
    end
    
    local placed_count = 0
    local max_actual_time = 0
    
    for i, point in ipairs(item_data.points) do
        local corrected_time = point.time * 0.5 
        local absolute_time = cursor_pos + corrected_time
 
        if corrected_time > max_actual_time then
            max_actual_time = corrected_time
        end

        local converted_value = ConvertValueForEnvelope(point.value, env_type)
        
        r.InsertEnvelopePoint(env, absolute_time, converted_value, point.shape or 0, 0, false)
        placed_count = placed_count + 1
        
    end
    
    corrected_length = max_actual_time
    last_time = cursor_pos + corrected_length
    
    local selected_count = 0
    for ptidx = 0, r.CountEnvelopePoints(env) - 1 do
        local retval, time, value, shape, tension, selected = r.GetEnvelopePointEx(env, -1, ptidx)
        if retval and time >= first_time and time <= last_time then  
            r.SetEnvelopePointEx(env, -1, ptidx, time, value, shape, tension, true, false)
            selected_count = selected_count + 1
         
        end
    end
     
    local conversion_success = TK_ConvertSelectedEnvelopePointsToAutomationItem(env)
    if not conversion_success then
        SetFooterMessage("Conversion failed (span too short)")
    end
    
    local automation_count_after = r.CountAutomationItems(env)
    local points_after_conversion = r.CountEnvelopePoints(env)
    
    if automation_count_after > initial_automation_items then
        local item_idx = automation_count_after - 1
        local item_pos = r.GetSetAutomationItemInfo(env, item_idx, "D_POSITION", 0, false)
        local item_len = r.GetSetAutomationItemInfo(env, item_idx, "D_LENGTH", 0, false)
        
        if math.abs(item_len - corrected_length) > 0.01 then  
            r.GetSetAutomationItemInfo(env, item_idx, "D_LENGTH", corrected_length, true)
        end

        r.GetSetAutomationItemInfo(env, item_idx, "D_LOOPSRC", enable_loop and 1 or 0, true)  
     
        r.GetSetAutomationItemInfo(env, item_idx, "D_PLAYRATE", 1.0, true)
    end
  
    
    for i = 0, r.CountAutomationItems(env) - 1 do
        r.GetSetAutomationItemInfo(env, i, "D_UISEL", 0, false)  
    end

    local cleaned_count = 0
    for ptidx = r.CountEnvelopePoints(env) - 1, 0, -1 do
        local retval, time, value, shape, tension, selected = r.GetEnvelopePointEx(env, -1, ptidx)
        if retval then
            if math.abs(time - first_time) < 0.001 or math.abs(time - last_time) < 0.001 then
                r.DeleteEnvelopePointEx(env, -1, ptidx)
                cleaned_count = cleaned_count + 1
            end
        end
    end
    

    local restored_count = 0
    local skipped_count = 0
    
    for _, orig_point in ipairs(original_points) do
        local point_exists = false
        for ptidx = 0, r.CountEnvelopePoints(env) - 1 do
            local retval, time, value, shape, tension, selected = r.GetEnvelopePointEx(env, -1, ptidx)
            if retval and math.abs(time - orig_point.time) < 0.001 then  
                point_exists = true
                break
            end
        end
        
        if not point_exists then
            r.InsertEnvelopePoint(env, orig_point.time, orig_point.value, orig_point.shape, orig_point.tension, false, false)
            restored_count = restored_count + 1
        else
            skipped_count = skipped_count + 1
        end
    end
    
    for ptidx = 0, r.CountEnvelopePoints(env) - 1 do
        local retval, time, value, shape, tension, selected = r.GetEnvelopePointEx(env, -1, ptidx)
        r.SetEnvelopePointEx(env, -1, ptidx, time, value, shape, tension, false, false)
    end
    
    r.Envelope_SortPoints(env)
    r.UpdateArrange()
    r.Undo_EndBlock("Create automation item with envelope restore", -1)
    
    local final_points = r.CountEnvelopePoints(env)
    local final_items = r.CountAutomationItems(env)

    local end_position = cursor_pos + corrected_length
    if move_edit_cursor then r.SetEditCurPos(end_position, true, false) end
    
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
        
        if r.ImGui_Button(ctx, "⚙️", settings_button_width, 0) then
            r.ImGui_OpenPopup(ctx, "settings_menu")
        end
        
        r.ImGui_PopStyleVar(ctx, 1)
        r.ImGui_PopStyleColor(ctx, 3)
        
        if r.ImGui_BeginPopup(ctx, "settings_menu") then
            local changed, new_value = r.ImGui_Checkbox(ctx, "🔄 Enable Loop", enable_loop)
            if changed then
                enable_loop = new_value
                SaveSettings()
            end
            
            local mec_changed, mec_value = r.ImGui_Checkbox(ctx, "▶ Move Edit Cursor", move_edit_cursor)
            if mec_changed then
                move_edit_cursor = mec_value
                SaveSettings()
            end
            
            local slo_changed, slo_value = r.ImGui_Checkbox(ctx, "Lines Only", show_lines_only)
            if slo_changed then
                show_lines_only = slo_value
                SaveSettings()
            end
            if r.ImGui_ColorButton(ctx, "##curve_color_btn", curve_color, 0, 20, 20) then
                r.ImGui_OpenPopup(ctx, "curve_color_picker")
            end
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
                SetFooterMessage("TK Automation Item Manager - Version 0.0.4")
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
                if r.ImGui_MenuItem(ctx, "🗑️ Delete") then
                    DeleteAutomationItem(item, i)
                end
                
                if r.ImGui_MenuItem(ctx, "✏️ Rename") then
                    RenameAutomationItem(item, i)
                end
                
                r.ImGui_Separator(ctx)
                
                if r.ImGui_MenuItem(ctx, "📁 Show in Explorer") then
                    ShowItemInExplorer(item)
                end
                
                if r.ImGui_MenuItem(ctx, "📋 Copy Path") then
                    CopyItemPath(item)
                end
                
                r.ImGui_EndPopup(ctx)
            end

            if r.ImGui_IsItemHovered(ctx) then
                r.ImGui_BeginTooltip(ctx)
                r.ImGui_Text(ctx, item.name or "Unknown")
                r.ImGui_Text(ctx, "Click to load as envelope points")

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
    local top_cols = 4
    local top_btn_w = math.max(60, math.floor((available_width - spacing_x) / top_cols))
    
    if r.ImGui_Button(ctx, "Refresh", top_btn_w, 0) then
        ScanAutomationItems()
        SetFooterMessage("Automation items refreshed! Found " .. #automation_items .. " items")
    end
    
    r.ImGui_SameLine(ctx)

    if r.ImGui_Button(ctx, "Convert Points", top_btn_w, 0) then
        local success = ConvertSelectedEnvelopePointsToAutomationItem()
        if success then
            SetFooterMessage("Successfully converted envelope points to automation item")
        else
            SetFooterMessage("Failed to convert - check envelope selection and points")
        end
    end
    
    r.ImGui_SameLine(ctx)

    if r.ImGui_Button(ctx, "Save", top_btn_w, 0) then
        r.Main_OnCommand(42092, 0)  
        SetFooterMessage("Save automation item command executed")
    end

    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Open AI Folder", top_btn_w, 0) then
        if EnsureAutomationFolderExists() then
            OpenPathInExplorer(automation_folder)
        end
    end

    local bottom_col_w = math.max(80, math.floor((available_width - spacing_x) / 2))

    if r.ImGui_Button(ctx, "Insert New", bottom_col_w, 0) then
        r.Main_OnCommand(42082, 0)
        SetFooterMessage("Inserted automation item")
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Edge points", bottom_col_w, 0) then
        r.Main_OnCommand(42209, 0)
        SetFooterMessage("Added edge points")
    end
    
    if r.ImGui_Button(ctx, "Pool (duplicate)", bottom_col_w, 0) then
        r.Main_OnCommand(42085, 0)
        SetFooterMessage("Pooled duplicate created")
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Unpool (sel)", bottom_col_w, 0) then
        r.Main_OnCommand(42084, 0)
        SetFooterMessage("Unpooled selected item(s)")
    end
    
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
    -- ReaImGui ruimt automatisch contexts op, geen handmatige cleanup nodig
    ctx = nil
end

r.atexit(cleanup)

Main()
