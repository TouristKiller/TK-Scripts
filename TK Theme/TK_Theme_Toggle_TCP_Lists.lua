-- @description TK Theme Dark: show/hide the TCP FX and IO columns
-- @author TouristKiller
-- @version 0.9.3
-- Run from the button in the TCP (TK_Theme_Rebuild.lua registers this script
-- and the generator wires the button to it). Flips the theme parameters for
-- the FX list and send list sections between off and their last position,
-- for layouts A, B and C.
local r = reaper
local SECTION = "TK_Theme_TCP_Lists"
local DEFAULTS = { Fx = 7, Send = 8 }
-- REAPER's own options, off on a new install: with them off the columns stay
-- empty whatever the theme's parameters say
local SHOW_FX, SHOW_SENDS = 40302, 40677

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
if r.GetToggleCommandState(SHOW_FX) == 1 then
    for _, p in ipairs(params) do
        if p.kind == "Fx" and p.value > 0 then shown = true end
    end
end

for _, p in ipairs(params) do
    if shown then
        if p.value > 0 then r.SetExtState(SECTION, p.name, tostring(p.value), true) end
        r.ThemeLayout_SetParameter(p.idx, 0, true)
    else
        local back = p.value > 0 and p.value or tonumber(r.GetExtState(SECTION, p.name)) or DEFAULTS[p.kind]
        r.ThemeLayout_SetParameter(p.idx, back, true)
    end
end
if not shown then
    for _, cmd in ipairs({ SHOW_FX, SHOW_SENDS }) do
        if r.GetToggleCommandState(cmd) ~= 1 then r.Main_OnCommand(cmd, 0) end
    end
end
r.ThemeLayout_RefreshAll()
