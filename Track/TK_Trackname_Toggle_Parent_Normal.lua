-- @description TK_Trackname_Toggle_Parent_Normal
-- @author TouristKiller
-- @version 1.0
-- @changelog:
--   v1.0: Initial release
-- @about Combo toggle for Parent + Normal track names. If both are on they turn off, otherwise both turn on

local r = reaper
local script_path = debug.getinfo(1,'S').source:match[[^@?(.*[\/])[^\/]-$]]
local json = dofile(script_path .. "json.lua")

local section = "TK_TRACKNAMES"
local keys = { "show_parent_tracks", "show_normal_tracks" }

local function SetButtonState(state)
    local _, _, sec, cmd = r.get_action_context()
    r.SetToggleCommandState(sec, cmd, state)
    r.RefreshToolbar2(sec, cmd)
end

local settings_json = r.GetExtState(section, "settings")
if settings_json == "" then return end

local settings = json.decode(settings_json)

local all_on = true
for _, k in ipairs(keys) do
    if not settings[k] then all_on = false break end
end

local new_val = not all_on
for _, k in ipairs(keys) do
    settings[k] = new_val
end

r.SetExtState(section, "settings", json.encode(settings), true)
r.SetExtState(section, "reload_settings", "1", false)

SetButtonState(new_val and 1 or 0)
r.UpdateArrange()
