-- @description TK Theme Dark: show/hide the TCP FX and IO columns
-- @author TouristKiller
-- @version 0.9.1
-- Run from the button in the TCP (TK_Theme_Rebuild.lua registers this script
-- and the generator wires the button to it). Flips the theme parameters for
-- the FX list and send list sections between off and their last position,
-- for layouts A, B and C.
local r = reaper
local SECTION = "TK_Theme_TCP_Lists"
local DEFAULTS = { Fx = 7, Send = 8 }

-- e.g. LayoutA-tcpFxLocation, LayoutC-tcpSendLocation
local params = {}
local i = 0
while true do
    local name, _, value = r.ThemeLayout_GetParameter(i)
    if not name then break end
    local lay, kind = name:match("^Layout([ABC])%-tcp(%a+)Location$")
    if lay and DEFAULTS[kind] then
        params[#params + 1] = { idx = i, name = name, kind = kind, value = value or 0 }
    end
    i = i + 1
end
if #params == 0 then return end

local shown = false
for _, p in ipairs(params) do
    if p.kind == "Fx" and p.value > 0 then shown = true end
end

for _, p in ipairs(params) do
    if shown then
        if p.value > 0 then r.SetExtState(SECTION, p.name, tostring(p.value), true) end
        r.ThemeLayout_SetParameter(p.idx, 0, true)
    else
        local back = tonumber(r.GetExtState(SECTION, p.name)) or DEFAULTS[p.kind]
        r.ThemeLayout_SetParameter(p.idx, back, true)
    end
end
r.ThemeLayout_RefreshAll()
