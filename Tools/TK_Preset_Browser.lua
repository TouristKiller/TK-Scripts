-- @description TK Preset Browser
-- @version 0.0.1
-- @author TouristKiller

--- IGNORE ---
-- =============================================================================
-- TK PRESET BROWSER - Quick Start Guide
-- =============================================================================
--
-- This script helps you browse presets and open plugins for various audio plugins in REAPER.
--
-- BASIC USAGE:
-- 1. First Time Setup:
--    - Click "Settings" button
--    - Add preset folders using "Add Path" (e.g., C:\Program Files\VSTPlugins\Presets)
--    - Click "Full Rescan" to scan all presets (takes time on first run)
--
-- 2. Browsing Presets:
--    - Use the search box to find presets by name or plugin
--    - Click on a preset in the list to select it
--    - Use "Open Plugin" to load the plugin on the selected track (if name is correct)
--
-- 3. Search Options:
--    - "Name only" - Search only in preset names
--    - "Plugin only" - Search only in plugin names
--    - Leave both unchecked to search everywhere
--
-- 4. Fixing Plugin Names:
--    - If "Open Plugin" doesn't work, the plugin name detection may be wrong
--    - Click "Manual Plugin Input" to manually set the correct plugin name
--    - Check "Apply to vendor" to apply the correction to all presets from same vendor
--    - The script remembers these corrections for future use
--
-- 5. Adding Custom Extensions:
--    - If your presets use uncommon file extensions, go to Settings
--    - Use "Add Extension" to add new file types (e.g., .myformat)
--    - Give it a descriptive name and it will be included in future scans
--
-- 6. Maintenance:
--    - Use "Update (Incremental)" for quick updates (only scans changed folders)
--    - Check "Console" for scan progress and any errors
--    - Plugin name corrections are automatically saved
--
-- SUPPORTED FORMATS:
-- VST3 (.vstpreset), VST (.fxp/.fxb), AU (.aupreset), CLAP (.clap-preset),
-- Kontakt (.nki/.nkm), Omnisphere (.omnisphere), and many more...
--
-- TIPS:
-- - Add your most-used preset folders first for faster scanning
-- - Use incremental updates after the initial full scan
-- - Manual plugin name corrections are saved and reused
--
-- =============================================================================

local script_name = "TK Preset Browser"
local ctx = reaper.ImGui_CreateContext(script_name)
local state = {
    scan_paths = {},
    presets = {},
    is_scanning = false,
    scan_progress = 0,
    total_items = 0,
    current_item = 0,
    search_query = "",
    filtered_presets = {},
    show_settings = false,
    new_path_input = "",
    new_ext_input = "",
    new_ext_name_input = "",
    scan_all_files = false,
    row_height = 20,
    search_name_only = false,
    search_plugin_only = false,
    scan_step = 0,  
    current_scan_path_index = 0,
    scan_start_time = 0,
    last_scan_time = 0,
    total_scan_time = 0,
    dir_timestamps = {},
    selected_preset = nil,
    selected_preset_row = -1,
    plugin_mappings = {},
    search_debounce_time = 0,
    search_needs_update = false,
    manual_plugin_input = "",
    manual_plugin_path_component = "",
    manual_plugin_original_name = "",
    show_manual_input = false,
    apply_to_vendor = false,
    show_console = false,
    console_log = {},
    console_max_lines = 500,
    show_reanalyze_warning = false,
}
local preset_extensions = {
    [".vstpreset"] = "VST3 Preset",
    [".fxp"] = "VST Preset",
    [".fxb"] = "VST Bank",
    [".fxpreset"] = "VST Preset",
    [".aupreset"] = "AU",
    [".clap-preset"] = "CLAP",
    [".clappreset"] = "CLAP",
    [".nksf"] = "NKS",
    [".nki"] = "Kontakt Instrument",
    [".nkm"] = "Kontakt Multi",
    [".nkr"] = "Reaktor",
    [".nks"] = "NKS",
    [".nmsv"] = "NI Massive",
    [".fm8"] = "NI FM8",
    [".absynth"] = "NI Absynth",
    [".kontakt"] = "Kontakt",
    [".battery"] = "NI Battery",
    [".guitar"] = "NI Guitar Rig",
    [".session"] = "NI Session Strings",
    [".scarbee"] = "NI Scarbee",
    [".nksfx"] = "NI Effects",
    [".nksv"] = "NI Vocals",
    [".nksd"] = "NI Drums",
    [".nksg"] = "NI Guitars",
    [".spf"] = "Spectrasonics",
    [".omnisphere"] = "Spectrasonics Omnisphere",
    [".prt_omn"] = "Spectrasonics Omnisphere",
    [".mlt_omn"] = "Spectrasonics Omnisphere",
    [".trilian"] = "Spectrasonics Trilian",
    [".keyscape"] = "Spectrasonics Keyscape",
    [".stylism"] = "Spectrasonics Stylism",
    [".distortion"] = "Spectrasonics Distortion",
    [".atmosphere"] = "Spectrasonics Atmosphere",
    [".rmx"] = "Spectrasonics RMX",
    [".stylus"] = "Spectrasonics Stylus RMX",
    [".xps"] = "Waves Preset",
    [".wps"] = "Waves Preset",
    [".ffp"] = "FabFilter Preset",
    [".ffx"] = "FabFilter FX Chain",
    [".vhp"] = "Valhalla Preset",
    [".khs"] = "Kilohearts Preset",
    [".phaseplant"] = "Kilohearts Phaseplant",
    [".snapheap"] = "Kilohearts Snap Heap",
    [".multiband"] = "Kilohearts Multiband",
    [".arcade"] = "Output Arcade",
    [".portal"] = "Output Portal",
    [".signal"] = "Output Signal",
    [".thermal"] = "Output Thermal",
    [".movement"] = "Output Movement",
    [".sps"] = "Spitfire Audio",
    [".spitfire"] = "Spitfire Audio",
    [".sfl"] = "Spitfire LABS",
    [".zpreset"] = "Spitfire",
    [".ewi"] = "EastWest Instrument",
    [".ewp"] = "EastWest Preset",
    [".play"] = "EastWest Play",
    [".hybrid"] = "Air Hybrid",
    [".vacuum"] = "Air Vacuum",
    [".transistor"] = "Air Transistor",
    [".structure"] = "Air Structure",
    [".loom"] = "Air Loom",
    [".xpand"] = "Air XPand!2",
    [".velocity"] = "Air Velocity",
    [".izp"] = "iZotope Preset",
    [".ozone"] = "iZotope Ozone",
    [".neutron"] = "iZotope Neutron",
    [".nectar"] = "iZotope Nectar",
    [".vinyl"] = "iZotope Vinyl",
    [".sft"] = "Softube Preset",
    [".tube"] = "Softube Tube",
    [".console"] = "Softube Console",
    [".sdp"] = "Slate Digital Preset",
    [".vcc"] = "Slate Digital VCC",
    [".fgx"] = "Slate Digital FG-X",
    [".pa"] = "Plugin Alliance",
    [".brainworx"] = "Brainworx",
    [".bx"] = "Brainworx",
    [".h2p"] = "U-He",
    [".uhe"] = "U-He",
    [".ksd"] = "Serum Preset",
    [".lfotool"] = "LFO Tool",
    [".vital"] = "Vital Synth",
    [".sylenth1bank"] = "Sylenth1 Bank",
    [".prf"] = "Nexus Preset",
    [".exs"] = "EXS24",
    [".syx"] = "SysEx",
    [".bank"] = "Bank",
    [".bundle"] = "Bundle",
    [".tal"] = "TAL Preset",
    [".helm"] = "Helm Synth",
    [".surge"] = "Surge XT",
    [".sfz"] = "SFZ",
    [".dspreset"] = "Decent Sampler",
    [".hsl"] = "HALion Sonic",
    [".vep"] = "Vienna Ensemble",
    [".fxchain"] = "FX Chain",
    [".preset"] = "Generic Preset",
}
local excluded_extensions = {
    [".mid"] = true,
    [".ini"] = true,
    [".json"] = true,
    [".txt"] = true,
    [".xml"] = true,
    [".xps"] = true,
    [".log"] = true,
    [".tmp"] = true,
    [".bak"] = true,
    [".old"] = true,
    [".exe"] = true,
    [".msi"] = true,
    [".bat"] = true,
    [".cmd"] = true,
    [".lnk"] = true,
    [".url"] = true,
    [".dll"] = true,
    [".sys"] = true,
    [".app"] = true,
    [".pkg"] = true,
    [".dmg"] = true,
    [".component"] = true,
    [".vst"] = true,
    [".vst3"] = true,
    [".aaxplugin"] = true,
    [".so"] = true,
    [".bin"] = true,
    [".run"] = true,
    [".desktop"] = true,
    [".alias"] = true,
    [".clap"] = true,
    [".command"] = true,
    [".plist"] = true,
    [".service"] = true,
    [".sh"] = true,
}
local custom_extensions = {}
local scan_messages = {
    "Time to get some coffee ☕",
    "Brewing presets... ☕",
    "Scanning the depths... 🔍",
    "Finding hidden gems... 💎",
    "Loading awesomeness... 🚀",
    "Gathering presets... 📚",
    "Exploring directories... 🗂️",
    "Uncovering treasures... 🏴‍☠️",
    "Loading your sound library... 🎵",
    "Scanning for magic... ✨",
    "Finding your next favorite sound... 🎸",
    "Loading presets... please wait... ⏳",
    "Almost there... 🎯",
    "Working hard... 💪",
    "Scanning directories... 📁",
    "Loading presets... 🔄",
    "Finding presets... 🔍",
    "Gathering sounds... 🎼",
    "Loading your collection... 📦",
    "Scanning for presets... 🔎"
}
function get_random_scan_message()
    return scan_messages[math.random(1, #scan_messages)]
end
function console_log(message)
    local timestamp = os.date("%H:%M:%S")
    local formatted_msg = string.format("[%s] %s", timestamp, message)
    table.insert(state.console_log, formatted_msg)
    if #state.console_log > state.console_max_lines then
        table.remove(state.console_log, 1)
    end
end
function get_database_path()
    local resource_path = reaper.GetResourcePath()
    return resource_path .. "\\TK_Preset_Browser_Database.txt"
end
function save_database()
    local db_path = get_database_path()
    local file = io.open(db_path, "w")
    if not file then
        return false
    end
    for _, preset in ipairs(state.presets) do
        local line = string.format("%s|%s|%s|%s|%s|%s\n",
            preset.name,
            preset.path,
            preset.plugin,
            preset.category or "",
            preset.type,
            preset.extension or ""
        )
        file:write(line)
    end
    file:close()
    return true
end
function save_database_as()
    local retval, filename = reaper.JS_Dialog_BrowseForSaveFile("Save Database As", "", "TK_Preset_Browser_Database.txt", "Text files (*.txt)\0*.txt\0All files (*.*)\0*.*\0")
    if retval == 1 and filename ~= "" then
        if not filename:match("%.txt$") then
            filename = filename .. ".txt"
        end
        local file = io.open(filename, "w")
        if not file then
            console_log("Failed to save database to: " .. filename .. "\n")
            return false
        end
        for _, preset in ipairs(state.presets) do
            local line = string.format("%s|%s|%s|%s|%s|%s\n",
                preset.name,
                preset.path,
                preset.plugin,
                preset.category or "",
                preset.type,
                preset.extension or ""
            )
            file:write(line)
        end
        file:close()
        console_log("Database exported to: " .. filename .. "\n")
        return true
    end
    return false
end
function load_database()
    local db_path = get_database_path()
    local file = io.open(db_path, "r")
    if not file then
        return false
    end
    state.presets = {}
    local line_count = 0
    for line in file:lines() do
        line_count = line_count + 1
        if not line:match("^%-%-") and line ~= "" then
            local name, path, plugin, category, type, extension = line:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)")
            if name and path then
                table.insert(state.presets, {
                    name = name,
                    path = path,
                    plugin = plugin,
                    category = category ~= "" and category or "Uncategorized",
                    type = type,
                    extension = extension
                })
                if plugin and plugin ~= "" and plugin ~= "Unknown" then
                    for part in path:gmatch("[^\\]+") do
                        if not state.plugin_mappings[part] then
                            local is_generic = part:match("^[Pp]resets?$") or 
                                              part:match("^[Ss]ounds?$") or 
                                              part:match("^[Bb]anks?$") or
                                              part:match("^Factory$") or
                                              part:match("^User$")
                            if not is_generic and path:find(part, 1, true) then
                                state.plugin_mappings[part] = plugin
                            end
                        end
                    end
                end
            end
        end
    end
    file:close()
    console_log(string.format("Loaded %d presets and rebuilt %d plugin mappings\n", 
        #state.presets, get_mapping_count()))
    filter_presets()
    return true
end
function save_plugin_mappings_to_file()
    local script_path = reaper.GetResourcePath() .. "/Scripts"
    local mapping_file = script_path .. "/TK_preset_browser_plugin_mappings.txt"
    local file = io.open(mapping_file, "w")
    if not file then
        console_log("Error: Could not create plugin mappings file\n")
        return false
    end
    file:write("# TK Preset Browser - Plugin Mappings\n")
    file:write("# Format: PathComponent|PluginName\n")
    file:write("# This file maps folder names to REAPER plugin names\n\n")
    local sorted_mappings = {}
    for detected, actual in pairs(state.plugin_mappings) do
        table.insert(sorted_mappings, {detected = detected, actual = actual})
    end
    table.sort(sorted_mappings, function(a, b) return a.detected < b.detected end)
    for _, mapping in ipairs(sorted_mappings) do
        file:write(mapping.detected .. "|" .. mapping.actual .. "\n")
    end
    file:close()
    console_log(string.format("Saved %d plugin mappings to: %s\n", #sorted_mappings, mapping_file))
    return true
end
function get_mapping_count()
    local count = 0
    for _ in pairs(state.plugin_mappings) do
        count = count + 1
    end
    return count
end
function load_plugin_mappings_from_file()
    local script_path = reaper.GetResourcePath() .. "/Scripts"
    local mapping_file = script_path .. "/TK_preset_browser_plugin_mappings.txt"
    local file = io.open(mapping_file, "r")
    if not file then
        console_log("No plugin mappings file found\n")
        return false
    end
    local count = 0
    for line in file:lines() do
        if not line:match("^%s*#") and not line:match("^%s*$") then
            local detected, actual = line:match("([^|]+)|(.+)")
            if detected and actual then
                state.plugin_mappings[detected] = actual
                count = count + 1
            end
        end
    end
    file:close()
    console_log(string.format("Loaded %d plugin mappings from: %s\n", count, mapping_file))
    for _, preset in ipairs(state.presets) do
        if preset.plugin == "Unknown" or not preset.plugin then
            local plugin_info = get_plugin_info_from_path(preset.path)
            if plugin_info then
                preset.plugin = plugin_info
            end
        end
    end
    filter_presets()
    return true
end
function get_settings_path()
    return reaper.GetResourcePath() .. "/Scripts/TK_preset_browser_settings.txt"
end
function get_settings_backup_path()
    return reaper.GetResourcePath() .. "/Scripts/TK_preset_browser_settings_backup.txt"
end
function save_settings()
    local settings_file = get_settings_path()
    local backup_file = get_settings_backup_path()
    local current = io.open(settings_file, "r")
    if current then
        local content = current:read("*all")
        current:close()
        local backup = io.open(backup_file, "w")
        if backup then
            backup:write(content)
            backup:close()
        end
    end
    local file = io.open(settings_file, "w")
    if not file then
        console_log("ERROR: Could not save settings file!\n")
        return false
    end
    file:write("# TK Preset Browser Settings\n")
    file:write("# Auto-saved: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n\n")
    file:write("[SCAN_PATHS]\n")
    for _, path in ipairs(state.scan_paths) do
        file:write(path .. "\n")
    end
    file:write("\n")
    file:write("[CUSTOM_EXTENSIONS]\n")
    for ext, name in pairs(custom_extensions) do
        file:write(ext .. "|" .. name .. "\n")
    end
    file:write("\n")
    file:write("[OPTIONS]\n")
    file:write("scan_all_files=" .. (state.scan_all_files and "1" or "0") .. "\n")
    file:write("search_name_only=" .. (state.search_name_only and "1" or "0") .. "\n")
    file:write("search_plugin_only=" .. (state.search_plugin_only and "1" or "0") .. "\n")
    file:write("last_scan_time=" .. state.last_scan_time .. "\n")
    file:write("\n")
    file:write("[DIR_TIMESTAMPS]\n")
    local count = 0
    for dir, timestamp in pairs(state.dir_timestamps) do
        file:write(dir .. "|" .. timestamp .. "\n")
        count = count + 1
    end
    console_log(string.format("Note: Saved %d directory timestamps\n", count))
    file:write("\n")
    file:write("[PLUGIN_MAPPINGS]\n")
    for detected, actual in pairs(state.plugin_mappings) do
        file:write(detected .. "|" .. actual .. "\n")
    end
    file:close()
    return true
end
function load_settings()
    local settings_file = get_settings_path()
    local backup_file = get_settings_backup_path()
    local file = io.open(settings_file, "r")
    local using_backup = false
    if not file then
        file = io.open(backup_file, "r")
        if file then
            using_backup = true
            console_log("⚠️ Main settings file not found, using backup\n")
        else
            return
        end
    end
    if not file then return end
    local section = nil
    local line_num = 0
    local loaded_paths = 0
    local loaded_extensions = 0
    local loaded_timestamps = 0
    local loaded_mappings = 0
    for line in file:lines() do
        line_num = line_num + 1
        if line:match("^#") or line:match("^%s*$") then
        elseif line:match("^%[(.+)%]") then
            section = line:match("^%[(.+)%]")
        elseif section == "SCAN_PATHS" then
            table.insert(state.scan_paths, line)
            loaded_paths = loaded_paths + 1
        elseif section == "CUSTOM_EXTENSIONS" then
            local ext, name = line:match("([^|]+)|(.+)")
            if ext and name and not excluded_extensions[ext] then
                custom_extensions[ext] = name
                loaded_extensions = loaded_extensions + 1
            end
        elseif section == "OPTIONS" then
            local key, value = line:match("([^=]+)=(.+)")
            if key == "scan_all_files" then
                state.scan_all_files = (value == "1")
            elseif key == "search_name_only" then
                state.search_name_only = (value == "1")
            elseif key == "search_plugin_only" then
                state.search_plugin_only = (value == "1")
            elseif key == "last_scan_time" then
                state.last_scan_time = tonumber(value) or 0
                console_log(string.format("Loaded last_scan_time: %d\n", state.last_scan_time))
            end
        elseif section == "DIR_TIMESTAMPS" then
            local dir, timestamp = line:match("([^|]+)|(.+)")
            if dir and timestamp then
                state.dir_timestamps[dir] = tonumber(timestamp) or 0
                loaded_timestamps = loaded_timestamps + 1
            end
        elseif section == "PLUGIN_MAPPINGS" then
            local detected, actual = line:match("([^|]+)|(.+)")
            if detected and actual then
                state.plugin_mappings[detected] = actual
                loaded_mappings = loaded_mappings + 1
            end
        end
    end
    file:close()
    if using_backup then
        console_log(string.format("✓ Restored from backup: %d paths, %d extensions, %d mappings\n", 
            loaded_paths, loaded_extensions, loaded_mappings))
        save_settings()
    else
        console_log(string.format("✓ Loaded settings: %d paths, %d extensions, %d timestamps, %d mappings\n", 
            loaded_paths, loaded_extensions, loaded_timestamps, loaded_mappings))
    end
end
function apply_path_mapping(path_component, plugin_name)
    if not path_component or not plugin_name or path_component == "" or plugin_name == "" then
        return 0
    end
    local count = 0
    for _, preset in ipairs(state.presets) do
        if preset.path and preset.path:find(path_component, 1, true) then
            preset.plugin = plugin_name
            count = count + 1
        end
    end
    state.plugin_mappings[path_component] = plugin_name
    save_settings()
    save_database()
    return count
end
function apply_plugin_name_limited(original_plugin_name, new_plugin_name)
    if not original_plugin_name or not new_plugin_name or new_plugin_name == "" then
        return 0
    end
    local count = 0
    for _, preset in ipairs(state.presets) do
        if preset.plugin == original_plugin_name then
            preset.plugin = new_plugin_name
            count = count + 1
        end
    end
    save_database()
    return count
end
function apply_path_structure_to_vendor(sample_preset_path, plugin_path_component)
    local known_vendors = {
        "FabFilter", "Waves", "iZotope", "Native Instruments", "Spectrasonics",
        "Arturia", "u-he", "Valhalla", "Soundtoys", "Plugin Alliance",
        "Softube", "Universal Audio", "UAD", "Slate Digital", "Kilohearts",
        "Output", "Spitfire", "EastWest", "AIR", "Avid", "NI", "Xfer",
        "Synapse Audio", "LennarDigital", "Rob Papen", "Reveal Sound",
        "Tone2", "Vengeance", "reFX", "Image-Line", "Cakewalk", "IK Multimedia",
        "Positive Grid", "Sugar Bytes", "Steinberg", "PreSonus", "SSL",
        "Sonnox", "McDSP", "FXpansion", "Celemony", "Eventide", "Lexicon",
        "TC Electronic", "Focusrite", "Brainworx", "Acustica Audio", "Oeksound",
        "Tokyo Dawn Labs", "TDR", "Voxengo", "DMG Audio", "Cytomic", "PSPaudioware",
        "UJAM"
    }
    local detected_vendor = nil
    local vendor_folder_name = nil
    for part in sample_preset_path:gmatch("[^\\]+") do
        for _, vendor in ipairs(known_vendors) do
            if part:lower() == vendor:lower() or part:find(vendor, 1, true) then
                detected_vendor = vendor
                vendor_folder_name = part
                break
            end
        end
        if detected_vendor then break end
    end
    if not detected_vendor then
        console_log("No known vendor detected in path\n")
        return 0
    end
    local sample_parts = {}
    for part in sample_preset_path:gmatch("[^\\]+") do
        table.insert(sample_parts, part)
    end
    local vendor_index = nil
    local component_index = nil
    for i, part in ipairs(sample_parts) do
        if part == vendor_folder_name then
            vendor_index = i
        end
        if part == plugin_path_component and vendor_index then
            component_index = i
            break
        end
    end
    if not vendor_index or not component_index then
        console_log("Could not locate vendor or component in path\n")
        return 0
    end
    local offset_from_vendor = component_index - vendor_index
    console_log(string.format("Detected vendor: %s (folder: %s)\n", detected_vendor, vendor_folder_name))
    console_log(string.format("Plugin component '%s' is at position %d after vendor folder\n", plugin_path_component, offset_from_vendor))
    local count = 0
    local updated_plugins = {}
    for _, preset in ipairs(state.presets) do
        local preset_parts = {}
        for part in preset.path:gmatch("[^\\]+") do
            table.insert(preset_parts, part)
        end
        local preset_vendor_index = nil
        for i, part in ipairs(preset_parts) do
            if part == vendor_folder_name then
                preset_vendor_index = i
                break
            end
        end
        if preset_vendor_index then
            local target_index = preset_vendor_index + offset_from_vendor
            if target_index > 0 and target_index <= #preset_parts then
                local new_plugin_name = preset_parts[target_index]
                local is_generic = new_plugin_name:match("^[Pp]resets?$") or 
                                  new_plugin_name:match("^[Ss]ounds?$") or 
                                  new_plugin_name:match("^[Bb]anks?$") or
                                  new_plugin_name:match("^Factory$") or
                                  new_plugin_name:match("^User$") or
                                  new_plugin_name:match("%.[^%.]+$")
                if not is_generic and new_plugin_name ~= preset.plugin then
                    preset.plugin = new_plugin_name
                    updated_plugins[new_plugin_name] = (updated_plugins[new_plugin_name] or 0) + 1
                    count = count + 1
                end
            end
        end
    end
    save_database()
    if count > 0 then
        console_log(string.format("\nApplied %s plugin structure to %d presets:\n", detected_vendor, count))
        for plugin, plugin_count in pairs(updated_plugins) do
            console_log(string.format("  - %s: %d presets\n", plugin, plugin_count))
        end
    else
        console_log("No presets were updated\n")
    end
    return count
end
function count_total_items(path)
    local count = 0
    local i = 0
    repeat
        local file = reaper.EnumerateFiles(path, i)
        if file then
            count = count + 1
        end
        i = i + 1
    until not file
    i = 0
    repeat
        local subdir = reaper.EnumerateSubdirectories(path, i)
        if subdir then
            count = count + 1
            count = count + count_total_items(path .. "\\" .. subdir)
        end
        i = i + 1
    until not subdir
    return count
end
function get_directory_modtime(path)
    local newest_time = 0
    local i = 0
    repeat
        local file = reaper.EnumerateFiles(path, i)
        if file then
            local full_path = path .. "\\" .. file
            local file_handle = io.open(full_path, "r")
            if file_handle then
                file_handle:close()
                newest_time = os.time()
            end
        end
        i = i + 1
    until not file
    return newest_time
end
function directory_needs_scan(path, last_scan_time)
    if not state.dir_timestamps[path] then
        console_log(string.format("Directory %s has no timestamp, needs scan\n", path))
        return true
    end
    
    local stored_timestamp = state.dir_timestamps[path]
    local current_time = os.time()
    local time_since_scan = current_time - stored_timestamp
    
    console_log(string.format("Directory %s: stored=%d, last_scan=%d, current=%d, age=%d seconds, needs_scan=%s\n", 
        path, stored_timestamp, last_scan_time, current_time, time_since_scan, 
        (stored_timestamp < last_scan_time) and "YES" or "NO"))
    
    if stored_timestamp and stored_timestamp >= last_scan_time then
        return false
    end
    
    local current_file_count = 0
    local max_count_check = 50
    local i = 0
    repeat
        local file = reaper.EnumerateFiles(path, i)
        if file then
            local ext = file:match("(%.[^%.]+)$")
            if ext then
                ext = ext:lower()
                if (preset_extensions[ext] or custom_extensions[ext] or state.scan_all_files) and not excluded_extensions[ext] then
                    current_file_count = current_file_count + 1
                    local stored_count = state.dir_timestamps[path .. "_count"]
                    if stored_count and current_file_count > stored_count then
                        return true
                    end
                end
            end
        end
        i = i + 1
    until not file or i >= max_count_check
    local stored_count = state.dir_timestamps[path .. "_count"]
    if stored_count and stored_count == current_file_count and i < max_count_check then
        return false
    end
    return true
end
function scan_directory(path, results)
    results = results or {}
    local file_count = 0
    local i = 0
    repeat
        local file = reaper.EnumerateFiles(path, i)
        if file then
            file_count = file_count + 1
            state.current_item = state.current_item + 1
            state.scan_progress = state.current_item / state.total_items
            local full_path = path .. "\\" .. file
            local ext = file:match("(%.[^%.]+)$")
            if ext then
                ext = ext:lower()
                local preset_type = preset_extensions[ext] or custom_extensions[ext]
                if (preset_type or state.scan_all_files) and not excluded_extensions[ext] then
                    local plugin_name = nil
                    for part in full_path:gmatch("[^\\]+") do
                        if state.plugin_mappings[part] then
                            plugin_name = state.plugin_mappings[part]
                            break
                        end
                    end
                    local category, format_hint
                    if not plugin_name then
                        plugin_name, category, format_hint = get_plugin_info_from_path(full_path)
                    else
                        local _, cat, fmt = get_plugin_info_from_path(full_path)
                        category = cat
                        format_hint = fmt
                    end
                    if format_hint and preset_type and preset_type:match("^VST") then
                        preset_type = format_hint .. " Preset"
                    end
                    table.insert(results, {
                        name = file,
                        path = full_path,
                        type = preset_type or ("Unknown " .. ext),
                        plugin = plugin_name,
                        category = category,
                        extension = ext
                    })
                end
            end
        end
        i = i + 1
    until not file
    state.dir_timestamps[path] = state.last_scan_time
    state.dir_timestamps[path .. "_count"] = file_count
    i = 0
    repeat
        local subdir = reaper.EnumerateSubdirectories(path, i)
        if subdir then
            state.current_item = state.current_item + 1
            state.scan_progress = state.current_item / state.total_items
            scan_directory(path .. "\\" .. subdir, results)
        end
        i = i + 1
    until not subdir
    return results
end
function get_plugin_info_from_path(path)
    local plugin_name = nil
    local category = "Uncategorized"
    local format_hint = nil
    local known_vendors = {
        "FabFilter", "Waves", "iZotope", "Native Instruments", "Spectrasonics",
        "Arturia", "u-he", "Valhalla", "Soundtoys", "Plugin Alliance",
        "Softube", "Universal Audio", "UAD", "Slate Digital", "Kilohearts",
        "Output", "Spitfire", "EastWest", "AIR", "Avid", "NI", "Xfer",
        "Synapse Audio", "LennarDigital", "Rob Papen", "Reveal Sound",
        "Tone2", "Vengeance", "reFX", "Image-Line", "Cakewalk", "IK Multimedia",
        "Positive Grid", "Sugar Bytes", "Steinberg", "PreSonus", "SSL",
        "Sonnox", "McDSP", "FXpansion", "Celemony", "Eventide", "Lexicon",
        "TC Electronic", "Focusrite", "Brainworx", "Acustica Audio", "Oeksound",
        "Tokyo Dawn Labs", "TDR", "Voxengo", "DMG Audio", "Cytomic", "PSPaudioware",
        "UJAM"
    }
    local path_parts = {}
    for part in path:gmatch("[^\\]+") do
        table.insert(path_parts, part)
    end
    if path:match("VST3 Presets") or path:match("VST3") then
        format_hint = "VST3"
    elseif path:match("\\[Cc]lap\\") or path:match("\\CLAP\\") then
        format_hint = "CLAP"
    elseif path:match("VST") and not path:match("VST3") then
        format_hint = "VST2"
    elseif path:match("AU") or path:match("Audio Units") then
        format_hint = "AU"
    end
    local vendor_found = false
    local potential_plugin = nil
    local potential_category = nil
    for i, part in ipairs(path_parts) do
        local is_generic = part:match("^[Pp]resets?$") or 
                          part:match("^[Ss]ounds?$") or 
                          part:match("^[Bb]anks?$") or
                          part:match("^[Ll]ibraries$") or
                          part:match("^VST3? Presets?$") or
                          part:match("^CLAP") or
                          part:match("^Factory") or
                          part:match("^User") or
                          part == "presets" or
                          part == "Presets"
        if not is_generic then
            local is_vendor = false
            for _, vendor in ipairs(known_vendors) do
                if part:lower() == vendor:lower() or part:find(vendor, 1, true) then
                    is_vendor = true
                    vendor_found = true
                    break
                end
            end
            if vendor_found and not is_vendor and not plugin_name then
                plugin_name = part
            elseif not vendor_found and not is_vendor and not potential_plugin then
                potential_plugin = part
            end
            if plugin_name and not category or category == "Uncategorized" then
                if i > 1 and not is_generic and part ~= plugin_name then
                    category = part
                end
            elseif potential_plugin and i > 1 and not potential_category then
                potential_category = part
            end
        end
    end
    if not plugin_name then
        plugin_name = potential_plugin
    end
    if (not category or category == "Uncategorized") and potential_category then
        category = potential_category
    end
    if not plugin_name then
        plugin_name = path:match("VST3 Presets\\[^\\]+\\([^\\]+)\\") or
                     path:match("VST3 Presets\\([^\\]+)\\")
        if not plugin_name then
            plugin_name = path:match("\\([^\\]+)\\[Pp]resets")
        end
        if not plugin_name then
            plugin_name = path:match("\\([^\\]+)\\[Ss]ounds") or
                         path:match("\\([^\\]+)\\[Bb]anks")
        end
    end
    if plugin_name and (not category or category == "Uncategorized") then
        category = path:match(plugin_name .. "\\([^\\]+)\\") or
                  path:match("\\[Pp]resets?\\([^\\]+)\\") or
                  path:match("\\[Ss]ounds\\([^\\]+)\\") or
                  "Uncategorized"
    end
    if not plugin_name then
        plugin_name = path:match("\\([^\\]+)$") or "Unknown"
    end
    if plugin_name then
        plugin_name = plugin_name:gsub("%.vst3$", "")
        plugin_name = plugin_name:gsub("%.clap$", "")
        plugin_name = plugin_name:gsub("%.component$", "")
    end
    return plugin_name, category, format_hint
end
function filter_presets()
    state.filtered_presets = {}
    local query = state.search_query:lower()
    if query == "" then
        -- Copy all presets instead of using reference
        for _, preset in ipairs(state.presets) do
            table.insert(state.filtered_presets, preset)
        end
        console_log(string.format("Filtered presets: showing all %d presets (no search query)", #state.filtered_presets))
    else
        for _, preset in ipairs(state.presets) do
            local match = false
            if state.search_plugin_only then
                local plugin_lower = (preset.plugin or ""):lower()
                match = plugin_lower:find(query, 1, true)
            elseif state.search_name_only then
                local name_without_ext = preset.name:gsub("%.[^.]+$", ""):lower()
                match = name_without_ext:find(query, 1, true)
            else
                local name_without_ext = preset.name:gsub("%.[^.]+$", ""):lower()
                local path_lower = preset.path:lower()
                match = name_without_ext:find(query, 1, true) or 
                       path_lower:find(query, 1, true)
            end
            if match then
                table.insert(state.filtered_presets, preset)
            end
        end
        console_log(string.format("Filtered presets: found %d matches for query '%s'", #state.filtered_presets, query))
    end
end
function scan_all_paths_async()
    if state.is_scanning then return end
    state.is_scanning = true
    state.presets = {}
    state.current_item = 0
    state.total_items = 0
    state.scan_step = 2  
    state.current_scan_path_index = 1
    state.scan_start_time = reaper.time_precise()
    state.last_scan_time = os.time()
    reaper.defer(scan_async_step)
end
function scan_async_step()
    if state.scan_step == 2 then
        if state.current_scan_path_index <= #state.scan_paths then
            local path = state.scan_paths[state.current_scan_path_index]
            scan_directory(path, state.presets)
            state.current_scan_path_index = state.current_scan_path_index + 1
            reaper.defer(scan_async_step)
        else
            state.scan_step = 3
            reaper.defer(scan_async_step)
        end
    elseif state.scan_step == 3 then
        state.is_scanning = false
        state.total_scan_time = reaper.time_precise() - state.scan_start_time
        filter_presets()
        save_database()
        save_settings()
        state.scan_step = 0
        state.current_scan_path_index = 0
    end
end
function scan_directory_incremental(path, results, existing_paths, checked_dirs)
    results = results or {}
    existing_paths = existing_paths or {}
    checked_dirs = checked_dirs or {}
    if checked_dirs[path] then
        return results
    end
    checked_dirs[path] = true
    if not directory_needs_scan(path, state.last_scan_time) then
        return results
    end
    local file_count = 0
    local i = 0
    repeat
        local file = reaper.EnumerateFiles(path, i)
        if file then
            local ext = file:match("(%.[^%.]+)$")
            if ext then
                ext = ext:lower()
                if (preset_extensions[ext] or custom_extensions[ext] or state.scan_all_files) and not excluded_extensions[ext] then
                    file_count = file_count + 1
                end
            end
        end
        i = i + 1
    until not file
    i = 0
    repeat
        local file = reaper.EnumerateFiles(path, i)
        if file then
            local full_path = path .. "\\" .. file
            local ext = file:match("(%.[^%.]+)$")
            if ext then
                ext = ext:lower()
                local preset_type = preset_extensions[ext] or custom_extensions[ext]
                if (preset_type or state.scan_all_files) and not excluded_extensions[ext] then
                    if not existing_paths[full_path] then
                        local plugin_name = nil
                        for part in full_path:gmatch("[^\\]+") do
                            if state.plugin_mappings[part] then
                                plugin_name = state.plugin_mappings[part]
                                break
                            end
                        end
                        local category, format_hint
                        if not plugin_name then
                            plugin_name, category, format_hint = get_plugin_info_from_path(full_path)
                        else
                            local _, cat, fmt = get_plugin_info_from_path(full_path)
                            category = cat
                            format_hint = fmt
                        end
                        if format_hint and preset_type and preset_type:match("^VST") then
                            preset_type = format_hint .. " Preset"
                        end
                        table.insert(results, {
                            name = file,
                            path = full_path,
                            type = preset_type or ("Unknown " .. ext),
                            plugin = plugin_name,
                            category = category,
                            extension = ext
                        })
                    end
                end
            end
        end
        i = i + 1
    until not file
    state.dir_timestamps[path] = state.last_scan_time
    state.dir_timestamps[path .. "_count"] = file_count
    i = 0
    repeat
        local subdir = reaper.EnumerateSubdirectories(path, i)
        if subdir then
            scan_directory_incremental(path .. "\\" .. subdir, results, existing_paths, checked_dirs)
        end
        i = i + 1
    until not subdir
    return results
end
function scan_incremental()
    state.last_scan_time = os.time()
    console_log(string.format("Starting incremental scan, last_scan_time=%d\n", state.last_scan_time))
    state.is_scanning = true
    local start_time = reaper.time_precise()
    local existing_paths = {}
    for _, preset in ipairs(state.presets) do
        existing_paths[preset.path] = true
    end
    local new_presets = {}
    for _, path in ipairs(state.scan_paths) do
        scan_directory_incremental(path, new_presets, existing_paths)
    end
    for _, preset in ipairs(new_presets) do
        table.insert(state.presets, preset)
    end
    state.is_scanning = false
    local scan_time = reaper.time_precise() - start_time
    filter_presets()
    if #new_presets > 0 then
        save_database()
    end
    save_settings()
    console_log(string.format("Incremental scan: %d new presets found in %.2f seconds\n", #new_presets, scan_time))
end
function find_plugin_on_track(plugin_name)
    local track = reaper.GetSelectedTrack(0, 0)
    if not track then return nil end
    local fx_count = reaper.TrackFX_GetCount(track)
    for i = 0, fx_count - 1 do
        local retval, fx_name = reaper.TrackFX_GetFXName(track, i, "")
        if retval then
            if fx_name:lower():find(plugin_name:lower(), 1, true) then
                return i
            end
        end
    end
    return nil
end
function load_plugin_on_track(plugin_name)
    local track = reaper.GetSelectedTrack(0, 0)
    if not track then 
        reaper.ShowMessageBox("Please select a track first", "No Track Selected", 0)
        return false
    end
    local mapped_name = state.plugin_mappings[plugin_name]
    if mapped_name and mapped_name ~= "" then
        console_log(string.format("\nUsing mapped name: %s -> %s\n", plugin_name, mapped_name))
        local fx_index = reaper.TrackFX_AddByName(track, mapped_name, false, -1)
        if fx_index >= 0 and fx_index < 16777216 then
            console_log("✓ Plugin loaded successfully!\n")
            reaper.TrackFX_Show(track, fx_index, 3)
            return true, fx_index
        else
            console_log("✗ Mapped name didn't work. Trying auto-detection...\n")
        end
    end
    local clean_name = plugin_name:gsub("%.vst3$", ""):gsub("%.clap$", ""):gsub("%.component$", "")
    local plugin_variations = {
        clean_name,
        "VST3: " .. clean_name,
        "VST: " .. clean_name,
        "VSTi: " .. clean_name,
        "VST3i: " .. clean_name,
        "AU: " .. clean_name,
        "AUi: " .. clean_name,
        "CLAP: " .. clean_name,
        "CLAPi: " .. clean_name,
        clean_name .. ".vst3",
        clean_name .. " (VST3)",
        clean_name .. " (VST)",
    }
    console_log(string.format("\nTrying to load plugin: %s\n", clean_name))
    for i, variant in ipairs(plugin_variations) do
        local fx_index = reaper.TrackFX_AddByName(track, variant, false, -1)
        if fx_index >= 0 and fx_index < 16777216 then
            console_log(string.format("✓ Loaded as: %s\n", variant))
            reaper.TrackFX_Show(track, fx_index, 3)
            if not state.plugin_mappings[plugin_name] then
                state.plugin_mappings[plugin_name] = variant
                save_settings()
                console_log(string.format("✓ Auto-saved mapping: %s -> %s\n", plugin_name, variant))
            end
            return true, fx_index
        end
    end
    console_log("✗ Plugin not found. Please create a manual mapping.\n")
    return false, nil
end
function draw_manual_input()
    reaper.ImGui_SetNextWindowSize(ctx, 500, 200, reaper.ImGui_Cond_FirstUseEver())
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 3.0)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 3.0)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x666666FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x888888FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0xAAAAAAFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_CheckMark(), 0xCCCCCCFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), 0x555555FF)
    local visible, open = reaper.ImGui_Begin(ctx, "Manual Plugin Input##" .. script_name, true)
    if visible then
        reaper.ImGui_Text(ctx, "Enter plugin name for path component:")
        reaper.ImGui_TextColored(ctx, 0x00FF00FF, state.manual_plugin_path_component)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Text(ctx, "Plugin name (as it appears in REAPER FX list):")
        reaper.ImGui_TextDisabled(ctx, "Example: VST3: FabFilter Pro-C 2 (FabFilter)")
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_SetNextItemWidth(ctx, -1)
        local input_changed, new_input = reaper.ImGui_InputText(ctx, "##manualinput", state.manual_plugin_input)
        if input_changed then
            state.manual_plugin_input = new_input
        end
        if reaper.ImGui_IsWindowAppearing(ctx) then
            reaper.ImGui_SetKeyboardFocusHere(ctx, -1)
        end
        if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter()) then
            if state.manual_plugin_input ~= "" then
                local count = apply_plugin_name_limited(state.manual_plugin_original_name, state.manual_plugin_input)
                console_log(string.format("Applied plugin name '%s' to %d presets (previously '%s')\n", 
                    state.manual_plugin_input, count, state.manual_plugin_original_name))
                filter_presets()
                state.manual_plugin_input = ""
                state.show_manual_input = false
            end
        end
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Spacing(ctx)
        if reaper.ImGui_Button(ctx, "Apply", 120) then
            if state.manual_plugin_input ~= "" then
                local count = apply_plugin_name_limited(state.manual_plugin_original_name, state.manual_plugin_input)
                console_log(string.format("Applied plugin name '%s' to %d presets (previously '%s')\n", 
                    state.manual_plugin_input, count, state.manual_plugin_original_name))
                filter_presets()
                state.manual_plugin_input = ""
                state.show_manual_input = false
            end
        end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Cancel", 120) then
            state.manual_plugin_input = ""
            state.show_manual_input = false
        end
    end
    reaper.ImGui_End(ctx)
    reaper.ImGui_PopStyleVar(ctx, 2)
    reaper.ImGui_PopStyleColor(ctx, 5)
    if not open then
        state.show_manual_input = false
        state.manual_plugin_input = ""
    end
end
function draw_console()
    reaper.ImGui_SetNextWindowSize(ctx, 500, 400, reaper.ImGui_Cond_FirstUseEver())
    reaper.ImGui_SetNextWindowPos(ctx, 100, 100, reaper.ImGui_Cond_FirstUseEver())
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 3.0)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 3.0)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x666666FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x888888FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0xAAAAAAFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_CheckMark(), 0xCCCCCCFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), 0x555555FF)
    local visible, open = reaper.ImGui_Begin(ctx, "Console Log", true)    if visible then
        if reaper.ImGui_Button(ctx, "Clear", 80) then
            state.console_log = {}
        end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Copy to Clipboard", 120) then
            local console_text = ""
            for i, message in ipairs(state.console_log) do
                console_text = console_text .. message
            end
            reaper.CF_SetClipboard(console_text)
            console_log("Console content copied to clipboard\n")
        end
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_Text(ctx, string.format("(%d messages)", #state.console_log))
        reaper.ImGui_Separator(ctx)
        for i, message in ipairs(state.console_log) do
            reaper.ImGui_TextWrapped(ctx, message)
        end
        reaper.ImGui_End(ctx)
    end
    reaper.ImGui_PopStyleVar(ctx, 2)
    reaper.ImGui_PopStyleColor(ctx, 5)
    if not open then
        state.show_console = false
    end
end
function draw_reanalyze_warning()
    if not state.show_reanalyze_warning then
        return
    end
    if not reaper.ImGui_IsPopupOpen(ctx, "Re-analyze Warning") then
        reaper.ImGui_OpenPopup(ctx, "Re-analyze Warning")
    end
    local center_x, center_y = reaper.ImGui_Viewport_GetCenter(reaper.ImGui_GetWindowViewport(ctx))
    reaper.ImGui_SetNextWindowPos(ctx, center_x, center_y, reaper.ImGui_Cond_Appearing(), 0.5, 0.5)
    if reaper.ImGui_BeginPopupModal(ctx, "Re-analyze Warning", true, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
        local manual_count = get_mapping_count()
        reaper.ImGui_PushTextWrapPos(ctx, 400)
        reaper.ImGui_TextColored(ctx, 0xFF4444FF, "WARNING: This action cannot be undone!")
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_TextWrapped(ctx, "Re-analyzing all plugin names will reset ALL plugin names to auto-detected values.")
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_TextWrapped(ctx, string.format("You currently have %d manual plugin mapping(s) that will be lost.", manual_count))
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_TextWrapped(ctx, "All plugins will be automatically detected again based on their file paths.")
        reaper.ImGui_PopTextWrapPos(ctx)
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)
        local button_width = 120
        local total_width = (button_width * 2) + 10
        local avail_width = reaper.ImGui_GetContentRegionAvail(ctx)
        reaper.ImGui_SetCursorPosX(ctx, (avail_width - total_width) / 2)
        if reaper.ImGui_Button(ctx, "OK - Proceed", button_width) then
            local count = 0
            for _, preset in ipairs(state.presets) do
                local plugin_info = get_plugin_info_from_path(preset.path)
                if plugin_info then
                    preset.plugin = plugin_info
                    count = count + 1
                end
            end
            state.plugin_mappings = {}
            save_database()
            save_settings()
            filter_presets()
            console_log(string.format("Re-analyzed %d presets. All plugin names reset to auto-detection.", count))
            state.show_reanalyze_warning = false
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Cancel", button_width) then
            state.show_reanalyze_warning = false
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        reaper.ImGui_EndPopup(ctx)
    end
end
function draw_settings()
    reaper.ImGui_SetNextWindowSize(ctx, 770, 0)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 3.0)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 3.0)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x666666FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x888888FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0xAAAAAAFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_CheckMark(), 0xCCCCCCFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), 0x555555FF)
    local settings_visible, settings_open = reaper.ImGui_Begin(ctx, "Settings##" .. script_name, true, 
        reaper.ImGui_WindowFlags_NoScrollbar() | reaper.ImGui_WindowFlags_NoResize())
    if settings_visible then
        reaper.ImGui_SeparatorText(ctx, "Database Info")
        reaper.ImGui_Text(ctx, string.format("Total Presets: %d", #state.presets))
        if state.last_scan_time > 0 then
            reaper.ImGui_Text(ctx, "Last Scan: " .. os.date("%Y-%m-%d %H:%M:%S", state.last_scan_time))
        end
        if state.total_scan_time > 0 then
            reaper.ImGui_Text(ctx, string.format("Last Scan Time: %.2f seconds", state.total_scan_time))
        end
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_SeparatorText(ctx, "Scan Paths")
        if reaper.ImGui_BeginChild(ctx, "PathsList", 0, 150) then
            for i, path in ipairs(state.scan_paths) do
                reaper.ImGui_Text(ctx, path)
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetWindowWidth(ctx) - 60)
                if reaper.ImGui_Button(ctx, "Remove##path" .. i, 50) then
                    table.remove(state.scan_paths, i)
                    save_settings()
                    break
                end
            end
            reaper.ImGui_EndChild(ctx)
        end
        reaper.ImGui_SetNextItemWidth(ctx, -110)
        local path_changed, new_path = reaper.ImGui_InputText(ctx, "##newpath", state.new_path_input)
        if path_changed then
            state.new_path_input = new_path
        end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Browse", 45) then
            local retval, selected_path = reaper.JS_Dialog_BrowseForFolder("Select Preset Directory", "")
            if retval == 1 then
                state.new_path_input = selected_path
            end
        end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Add", 45) then
            if state.new_path_input ~= "" then
                table.insert(state.scan_paths, state.new_path_input)
                state.new_path_input = ""
                save_settings()
            end
        end
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_SeparatorText(ctx, "Custom File Extensions")
        if reaper.ImGui_BeginChild(ctx, "ExtList", 0, 150) then
            if reaper.ImGui_BeginTable(ctx, "ExtTable", 3, reaper.ImGui_TableFlags_Borders()) then
                reaper.ImGui_TableSetupColumn(ctx, "Extension", reaper.ImGui_TableColumnFlags_WidthFixed(), 100)
                reaper.ImGui_TableSetupColumn(ctx, "Type Name", reaper.ImGui_TableColumnFlags_WidthStretch())
                reaper.ImGui_TableSetupColumn(ctx, "Action", reaper.ImGui_TableColumnFlags_WidthFixed(), 60)
                reaper.ImGui_TableHeadersRow(ctx)
                local to_remove = nil
                for ext, name in pairs(custom_extensions) do
                    reaper.ImGui_TableNextRow(ctx)
                    reaper.ImGui_TableSetColumnIndex(ctx, 0)
                    reaper.ImGui_Text(ctx, ext)
                    reaper.ImGui_TableSetColumnIndex(ctx, 1)
                    reaper.ImGui_Text(ctx, name)
                    reaper.ImGui_TableSetColumnIndex(ctx, 2)
                    if reaper.ImGui_Button(ctx, "Remove##" .. ext, 50) then
                        to_remove = ext
                    end
                end
                if to_remove then
                    custom_extensions[to_remove] = nil
                    save_settings()
                end
                reaper.ImGui_EndTable(ctx)
            end
            reaper.ImGui_EndChild(ctx)
        end
        reaper.ImGui_Text(ctx, "Extension (e.g., .tfx):")
        reaper.ImGui_SetNextItemWidth(ctx, 120)
        local ext_changed, new_ext = reaper.ImGui_InputText(ctx, "##newext", state.new_ext_input)
        if ext_changed then
            state.new_ext_input = new_ext
        end
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_Text(ctx, "Type Name:")
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_SetNextItemWidth(ctx, -110)
        local name_changed, new_name = reaper.ImGui_InputText(ctx, "##newextname", state.new_ext_name_input)
        if name_changed then
            state.new_ext_name_input = new_name
        end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Add##ext", 100) then
            if state.new_ext_input ~= "" and state.new_ext_name_input ~= "" then
                local ext = state.new_ext_input
                if not ext:match("^%.") then
                    ext = "." .. ext
                end
                ext = ext:lower()
                if excluded_extensions[ext] then
                    reaper.ShowMessageBox("This file extension is excluded because it contains generic files that would clutter the preset list.", "Extension Excluded", 0)
                else
                    custom_extensions[ext] = state.new_ext_name_input
                    save_settings()
                    state.new_ext_input = ""
                    state.new_ext_name_input = ""
                    console_log(string.format("Added extension '%s'. Starting incremental scan to find new presets...\n", ext))
                    reaper.defer(function()
                        scan_incremental()
                    end)
                end
                state.new_ext_input = ""
                state.new_ext_name_input = ""
                save_settings()
            end
        end
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_SeparatorText(ctx, "Excluded File Extensions")
        reaper.ImGui_TextWrapped(ctx, "These generic file types are automatically excluded to prevent cluttering the preset list:")
        if reaper.ImGui_BeginChild(ctx, "ExcludedExtList", 0, 80) then
            local excluded_list = {}
            for ext, _ in pairs(excluded_extensions) do
                table.insert(excluded_list, ext)
            end
            table.sort(excluded_list)
            local line_width = 0
            local max_line_width = 800
            local item_spacing = 8
            for i, ext in ipairs(excluded_list) do
                local ext_width = #ext * 8
                if line_width + ext_width > max_line_width and line_width > 0 then
                    local cursor_y = reaper.ImGui_GetCursorPosY(ctx)
                    reaper.ImGui_SetCursorPosY(ctx, cursor_y + 2)
                    reaper.ImGui_SetCursorPosX(ctx, 0)
                    line_width = 0
                end
                if line_width > 0 then
                    reaper.ImGui_SameLine(ctx)
                    reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + item_spacing)
                end
                reaper.ImGui_Text(ctx, ext)
                line_width = line_width + ext_width + item_spacing
            end
            reaper.ImGui_NewLine(ctx)
            reaper.ImGui_EndChild(ctx)
        end
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_SeparatorText(ctx, "Database Management")
        reaper.ImGui_TextWrapped(ctx, string.format("Total presets: %d (including %d unique plugin mappings)", #state.presets, get_mapping_count()))
        reaper.ImGui_Spacing(ctx)
        local button_width = 180
        if reaper.ImGui_Button(ctx, "Re-analyze All Plugin Names", button_width) then
            state.show_reanalyze_warning = true
        end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Export Database to File", button_width) then
            if save_database() then
                local db_path = get_database_path()
                console_log("Database exported to: " .. db_path .. "\n")
            end
        end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Export Database File As...", button_width) then
            save_database_as()
        end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Import Database from File", button_width) then
            if load_database() then
                console_log("Database imported successfully\n")
            end
        end
        reaper.ImGui_TextWrapped(ctx, "Database file: " .. get_database_path())
        reaper.ImGui_TextWrapped(ctx, "Contains all presets with their plugin names. Share this file to transfer your preset library.")
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_SeparatorText(ctx, "Options")
        local scan_all_changed, scan_all = reaper.ImGui_Checkbox(ctx, "Scan all files (includes unknown extensions)", state.scan_all_files)
        if scan_all_changed then
            state.scan_all_files = scan_all
            save_settings()
        end
        reaper.ImGui_End(ctx)
    end
    reaper.ImGui_PopStyleVar(ctx, 2)
    reaper.ImGui_PopStyleColor(ctx, 5)
    if not settings_open then
        state.show_settings = false
    end
end
function count_table(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end
function draw_preset_table_virtualized()
    if reaper.ImGui_BeginTable(ctx, "PresetTable", 4, reaper.ImGui_TableFlags_Borders() | reaper.ImGui_TableFlags_RowBg() | reaper.ImGui_TableFlags_ScrollY() | reaper.ImGui_TableFlags_Resizable()) then
        reaper.ImGui_TableSetupColumn(ctx, "Preset Name", reaper.ImGui_TableColumnFlags_WidthStretch())
        reaper.ImGui_TableSetupColumn(ctx, "Plugin", reaper.ImGui_TableColumnFlags_WidthFixed(), 150)
        reaper.ImGui_TableSetupColumn(ctx, "Ext", reaper.ImGui_TableColumnFlags_WidthFixed(), 60)
        reaper.ImGui_TableSetupColumn(ctx, "Path", reaper.ImGui_TableColumnFlags_WidthStretch())
        reaper.ImGui_TableHeadersRow(ctx)
        local total_presets = #state.filtered_presets
        if total_presets > 0 then
            local scroll_y = reaper.ImGui_GetScrollY(ctx)
            if not scroll_y then scroll_y = 0 end
            if type(scroll_y) ~= "number" then scroll_y = 0 end
            local window_height = reaper.ImGui_GetWindowHeight(ctx)
            if not window_height then window_height = 400 end
            if type(window_height) ~= "number" then window_height = 400 end
            if window_height <= 0 then window_height = 400 end
            local first_visible_row = math.max(0, math.floor(scroll_y / state.row_height) - 5)
            local visible_row_count = math.ceil(window_height / state.row_height) + 10
            local last_visible_row = math.min(first_visible_row + visible_row_count, total_presets)
            if first_visible_row > 0 then
                local dummy_height = first_visible_row * state.row_height
                reaper.ImGui_Dummy(ctx, 0, dummy_height)
            end
            for i = first_visible_row + 1, last_visible_row do
                local preset = state.filtered_presets[i]
                if preset then
                    reaper.ImGui_TableNextRow(ctx)
                    reaper.ImGui_TableSetColumnIndex(ctx, 0)
                    local name_without_ext = preset.name:gsub("%.[^.]+$", "")
                    local is_selected = (state.selected_preset_row == i)
                    local clicked = reaper.ImGui_Selectable(ctx, name_without_ext .. "##" .. i, is_selected, reaper.ImGui_SelectableFlags_SpanAllColumns())
                    if clicked then
                        state.selected_preset = preset
                        state.selected_preset_row = i
                    end
                    if reaper.ImGui_IsItemClicked(ctx, 1) then
                        reaper.ImGui_OpenPopup(ctx, "preset_context##" .. i)
                    end
                    if reaper.ImGui_BeginPopup(ctx, "preset_context##" .. i) then
                        reaper.ImGui_Text(ctx, "Preset: " .. name_without_ext)
                        reaper.ImGui_Separator(ctx)
                        if reaper.ImGui_Selectable(ctx, "Copy file path") then
                            reaper.CF_SetClipboard(preset.path)
                            console_log("Copied: " .. preset.path .. "\n")
                            reaper.ImGui_CloseCurrentPopup(ctx)
                        end
                        reaper.ImGui_EndPopup(ctx)
                    end
                    reaper.ImGui_TableSetColumnIndex(ctx, 1)
                    if preset.plugin and preset.plugin ~= "" and preset.plugin ~= "Unknown" then
                        reaper.ImGui_Text(ctx, preset.plugin)
                        if reaper.ImGui_IsItemClicked(ctx, 1) then
                            reaper.ImGui_OpenPopup(ctx, "edit_plugin##" .. i)
                        end
                        if reaper.ImGui_BeginPopup(ctx, "edit_plugin##" .. i) then
                            reaper.ImGui_Text(ctx, "Select plugin name from path:")
                            reaper.ImGui_Separator(ctx)
                            local vendor_toggled, vendor_checked = reaper.ImGui_Checkbox(ctx, "Apply structure to all plugins from this vendor", state.apply_to_vendor)
                            if vendor_toggled then
                                state.apply_to_vendor = vendor_checked
                            end
                            if state.apply_to_vendor then
                                reaper.ImGui_TextWrapped(ctx, "This will use the same folder structure for all plugins from the detected vendor (e.g., Waves, FabFilter, etc.)")
                            end
                            reaper.ImGui_Separator(ctx)
                            local path_parts = {}
                            for part in preset.path:gmatch("[^\\]+") do
                                table.insert(path_parts, part)
                            end
                            for idx, part in ipairs(path_parts) do
                                local is_filename = (idx == #path_parts)
                                local is_generic = part:match("^[Pp]resets?$") or 
                                                  part:match("^[Ss]ounds?$") or 
                                                  part:match("^[Bb]anks?$") or
                                                  part:match("^Factory$") or
                                                  part:match("^User$")
                                if not is_filename and not is_generic then
                                    if reaper.ImGui_Selectable(ctx, part .. "##pathpart" .. idx) then
                                        if state.apply_to_vendor then
                                            local count = apply_path_structure_to_vendor(preset.path, part)
                                            if count > 0 then
                                                filter_presets()
                                            else
                                                console_log("No vendor detected or structure could not be applied\n")
                                            end
                                        else
                                            local count = apply_path_mapping(part, part)
                                            console_log(string.format("Applied plugin name '%s' to %d presets\n", part, count))
                                            filter_presets()
                                        end
                                        reaper.ImGui_CloseCurrentPopup(ctx)
                                    end
                                    if reaper.ImGui_IsItemHovered(ctx) then
                                        reaper.ImGui_SetTooltip(ctx, "Use '" .. part .. "' as plugin name for all presets in this folder")
                                    end
                                end
                            end
                            reaper.ImGui_Separator(ctx)
                            if reaper.ImGui_Selectable(ctx, "Type plugin name manually...") then
                                state.manual_plugin_original_name = preset.plugin or "Unknown"
                                local path_parts = {}
                                for part in preset.path:gmatch("[^\\]+") do
                                    table.insert(path_parts, part)
                                end
                                for idx, part in ipairs(path_parts) do
                                    local is_filename = (idx == #path_parts)
                                    local is_generic = part:match("^[Pp]resets?$") or 
                                                      part:match("^[Ss]ounds?$") or 
                                                      part:match("^[Bb]anks?$") or
                                                      part:match("^Factory$") or
                                                      part:match("^User$")
                                    if not is_filename and not is_generic then
                                        state.manual_plugin_path_component = part
                                        break
                                    end
                                end
                                state.show_manual_input = true
                                reaper.ImGui_CloseCurrentPopup(ctx)
                            end
                            reaper.ImGui_EndPopup(ctx)
                        end
                    else
                        reaper.ImGui_TextDisabled(ctx, "Unknown")
                        if reaper.ImGui_IsItemClicked(ctx, 1) then
                            reaper.ImGui_OpenPopup(ctx, "set_plugin##" .. i)
                        end
                        if reaper.ImGui_BeginPopup(ctx, "set_plugin##" .. i) then
                            reaper.ImGui_Text(ctx, "Select plugin name from path:")
                            reaper.ImGui_Separator(ctx)
                            local path_parts = {}
                            for part in preset.path:gmatch("[^\\]+") do
                                table.insert(path_parts, part)
                            end
                            for idx, part in ipairs(path_parts) do
                                local is_filename = (idx == #path_parts)
                                local is_generic = part:match("^[Pp]resets?$") or 
                                                  part:match("^[Ss]ounds?$") or 
                                                  part:match("^[Bb]anks?$")
                                if not is_filename and not is_generic then
                                    if reaper.ImGui_Selectable(ctx, part .. "##pathpart" .. idx) then
                                        local count = apply_path_mapping(part, part)
                                        console_log(string.format("Applied plugin name '%s' to %d presets\n", part, count))
                                        filter_presets()
                                        reaper.ImGui_CloseCurrentPopup(ctx)
                                    end
                                end
                            end
                            reaper.ImGui_EndPopup(ctx)
                        end
                    end
                    reaper.ImGui_TableSetColumnIndex(ctx, 2)
                    reaper.ImGui_Text(ctx, preset.extension or "")
                    reaper.ImGui_TableSetColumnIndex(ctx, 3)
                    reaper.ImGui_Text(ctx, preset.path)
                end
            end
            local remaining_rows = total_presets - last_visible_row
            if remaining_rows > 0 then
                local dummy_height = remaining_rows * state.row_height
                reaper.ImGui_Dummy(ctx, 0, dummy_height)
            end
        end
        reaper.ImGui_EndTable(ctx)
    end
end
function loop()
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 3.0)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 3.0)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x666666FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x888888FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0xAAAAAAFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_CheckMark(), 0xCCCCCCFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), 0x555555FF)
    local visible, open = reaper.ImGui_Begin(ctx, script_name, true, reaper.ImGui_WindowFlags_None())
    if visible then
        if reaper.ImGui_Button(ctx, "Settings") then
            state.show_settings = not state.show_settings
        end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Console") then
            state.show_console = not state.show_console
        end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Full Rescan", 100, 0) then
            scan_all_paths_async()
        end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Update (Incremental)", 150, 0) then
            scan_incremental()
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Scans only for new presets.\nSkips directories that haven't changed since last scan.")
        end
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_Text(ctx, string.format("Found: %d | Showing: %d | Paths: %d | Ext: %d", 
            #state.presets,
            #state.filtered_presets,
            #state.scan_paths,
            count_table(custom_extensions)))
        if state.is_scanning then
            reaper.ImGui_Separator(ctx)
            if state.scan_step == 2 then
                reaper.ImGui_Text(ctx, string.format("Scanning... Path %d / %d (%d presets found)", 
                    state.current_scan_path_index, #state.scan_paths, #state.presets))
                local progress = 0
                if #state.scan_paths > 0 then
                    progress = (state.current_scan_path_index - 1) / #state.scan_paths
                end
                reaper.ImGui_ProgressBar(ctx, progress, -1, 0, get_random_scan_message())
            elseif state.scan_step == 3 then
                reaper.ImGui_Text(ctx, "Finalizing...")
                reaper.ImGui_ProgressBar(ctx, 1.0, -1, 0, "100%")
            end
        end
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Text(ctx, "Search:")
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_SetNextItemWidth(ctx, 300)
        local search_changed, new_query = reaper.ImGui_InputText(ctx, "##search", state.search_query)
        if search_changed then
            state.search_query = new_query
            state.search_debounce_time = reaper.time_precise()
            state.search_needs_update = true
            -- If search query is cleared, update immediately
            if new_query == "" then
                filter_presets()
                state.search_needs_update = false
            end
        end
        if state.search_needs_update then
            local time_since_change = reaper.time_precise() - state.search_debounce_time
            if time_since_change > 0.3 then
                filter_presets()
                state.search_needs_update = false
            end
        end
        reaper.ImGui_SameLine(ctx)
        local search_mode_changed, search_name_only = reaper.ImGui_Checkbox(ctx, "Name only", state.search_name_only)
        if search_mode_changed then
            state.search_name_only = search_name_only
            state.search_plugin_only = false
            save_settings()
            filter_presets()
        end
        reaper.ImGui_SameLine(ctx)
        local plugin_mode_changed, search_plugin_only = reaper.ImGui_Checkbox(ctx, "Plugin only", state.search_plugin_only)
        if plugin_mode_changed then
            state.search_plugin_only = search_plugin_only
            state.search_name_only = false
            save_settings()
            filter_presets()
        end
        reaper.ImGui_Separator(ctx)
        if reaper.ImGui_BeginChild(ctx, "PresetList", 0, -30) then
            draw_preset_table_virtualized()
            reaper.ImGui_EndChild(ctx)
        end
        reaper.ImGui_Separator(ctx)
            local has_selection = state.selected_preset ~= nil
            if not has_selection then
                reaper.ImGui_BeginDisabled(ctx)
            end
            if reaper.ImGui_Button(ctx, "Open Plugin", 120, 0) then
                if state.selected_preset and state.selected_preset.plugin then
                    load_plugin_on_track(state.selected_preset.plugin)
                end
            end
            if reaper.ImGui_IsItemHovered(ctx) and has_selection then
                reaper.ImGui_SetTooltip(ctx, string.format("Load %s on selected track", state.selected_preset.plugin or "plugin"))
            end
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, "Copy Path", 100, 0) then
                if state.selected_preset then
                    reaper.CF_SetClipboard(state.selected_preset.path)
                    console_log("Copied to clipboard: " .. state.selected_preset.path .. "\n")
                end
            end
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, "Open in Explorer", 120, 0) then
                if state.selected_preset then
                    reaper.CF_LocateInExplorer(state.selected_preset.path)
                end
            end
            if reaper.ImGui_IsItemHovered(ctx) and has_selection then
                reaper.ImGui_SetTooltip(ctx, "Open preset location in file browser")
            end
            if not has_selection then
                reaper.ImGui_EndDisabled(ctx)
            end
            reaper.ImGui_SameLine(ctx)
            if has_selection and state.selected_preset.plugin then
                reaper.ImGui_TextDisabled(ctx, string.format("Selected: %s (%s)", 
                    state.selected_preset.name:gsub("%.[^.]+$", ""), 
                    state.selected_preset.plugin))
            else
                reaper.ImGui_TextDisabled(ctx, "Double-click preset to load, or select and use buttons")
            end
        reaper.ImGui_End(ctx)
    end
    if state.show_settings then
        draw_settings()
    end
    if state.show_manual_input then
        draw_manual_input()
    end
    if state.show_console then
        draw_console()
    end
    draw_reanalyze_warning()
    reaper.ImGui_PopStyleVar(ctx, 2)
    reaper.ImGui_PopStyleColor(ctx, 5)
    if open then
        reaper.defer(loop)
    end
end
load_settings()
load_database()
reaper.defer(loop)
