local r = reaper
local script_path = debug.getinfo(1,'S').source:match[[^@?(.*[\/])[^\/]-$]]
local json = dofile(script_path .. "json.lua")

function Main()
    local section = "TK_TRACKNAMES"
    local settings_json = r.GetExtState(section, "settings")
    
    if settings_json ~= "" then
        local settings = json.decode(settings_json)
        settings.darker_parent_tracks = not settings.darker_parent_tracks
        settings_json = json.encode(settings)
        
        -- Sla nieuwe settings op
        r.SetExtState(section, "settings", settings_json, true)
        
        -- Force hoofdscript om settings opnieuw te laden
        r.SetExtState(section, "reload_settings", "1", false)
        
        -- Update UI
        r.UpdateArrange()
    end
end

Main()

