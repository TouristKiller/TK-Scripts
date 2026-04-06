-- @description TK_Trackname_Labels_Toggle
-- @author TouristKiller
-- @version 2.2
-- @changelog:
--   v2.2: Removed force_save, exclude show_settings_button
--   v2.0: Complete rewrite - robust save/restore of individual settings
-- @about Toggle all labels, icons, borders and text on/off while keeping track colors

local r = reaper
local section = "TK_TRACKNAMES"
local script_path = debug.getinfo(1,'S').source:match[[^@?(.*[\/])[^\/]-$]]
local json = dofile(script_path .. "json.lua")

local save_keys = {
    "show_label",
    "show_track_icons",
    "show_info_line",
    "label_border",
    "show_track_numbers",
    "show_parent_label",
    "show_first_fx",
    "show_envelope_names",
    "folder_border",
    "track_border",
    "show_freeze_icon",
    "text_hover_enabled",
    "text_hover_hide",
    "text_opacity",
    "envelope_text_opacity",
    "icon_opacity",
    "label_alpha",
    "border_opacity",
    "label_border_opacity",
    "overlay_grid_enabled",
}

local settings_json = r.GetExtState(section, "settings")
if settings_json == "" then return end

local settings = json.decode(settings_json)
local hidden = r.GetExtState(section, "labels_hidden_v2") == "1"

if hidden then
    local saved_json = r.GetExtState(section, "labels_saved_v2")
    if saved_json ~= "" then
        local saved = json.decode(saved_json)
        for _, key in ipairs(save_keys) do
            if saved[key] ~= nil then
                settings[key] = saved[key]
            end
        end
    end
    r.SetExtState(section, "labels_hidden_v2", "0", true)
else
    local saved = {}
    for _, key in ipairs(save_keys) do
        saved[key] = settings[key]
    end
    r.SetExtState(section, "labels_saved_v2", json.encode(saved), true)

    for _, key in ipairs(save_keys) do
        local val = settings[key]
        if type(val) == "boolean" then
            settings[key] = false
        elseif type(val) == "number" then
            settings[key] = 0.0
        end
    end
    r.SetExtState(section, "labels_hidden_v2", "1", true)
end

settings.hide_all_labels = false

r.SetExtState(section, "settings", json.encode(settings), true)
r.SetExtState(section, "reload_settings", "1", false)
r.UpdateArrange()
