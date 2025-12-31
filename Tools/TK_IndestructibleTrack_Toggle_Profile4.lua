-- @description TK Indestructible Track - Toggle Profile 4
-- @author TouristKiller
-- @version 1.4
-- @changelog:
--   + Store command ID in ExtState for main script toolbar sync

local r = reaper

local PROFILE_INDEX = 4
local EXTSTATE_SECTION = "TK_IndestructibleTrack"

local function GetCurrentState()
    local state_val = r.GetExtState(EXTSTATE_SECTION, "state_profile_" .. PROFILE_INDEX)
    if state_val ~= "" then
        return state_val == "1"
    end
    local DATA_DIR = r.GetResourcePath() .. "/Data/TK_IndestructibleTrack/"
    local CONFIG_FILE = DATA_DIR .. "TK_IndestructibleTrack_config.json"
    local file = io.open(CONFIG_FILE, "r")
    if not file then return false end
    local content = file:read("*all")
    file:close()
    if not content or content == "" then return false end
    local chunk = load("return " .. content:gsub('("[^"]*")%s*:', '[%1]='):gsub("%[", "{"):gsub("%]", "}"):gsub("null", "nil"))
    if chunk then
        local config = chunk()
        if config and config.profiles and config.profiles[PROFILE_INDEX] then
            return config.profiles[PROFILE_INDEX].enabled == true
        end
    end
    return false
end

local _, _, section, cmd = r.get_action_context()

r.SetExtState(EXTSTATE_SECTION, "cmd_profile_" .. PROFILE_INDEX, tostring(cmd), false)

local current_state = GetCurrentState()
r.SetToggleCommandState(section, cmd, current_state and 1 or 0)
r.RefreshToolbar2(section, cmd)

r.SetExtState(EXTSTATE_SECTION, "toggle_profile_" .. PROFILE_INDEX, "1", false)

r.defer(function()
    r.defer(function()
        local new_state = GetCurrentState()
        r.SetToggleCommandState(section, cmd, new_state and 1 or 0)
        r.RefreshToolbar2(section, cmd)
    end)
end)
