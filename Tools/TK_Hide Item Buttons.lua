-- @description TK_Hide Item Buttons
-- @author TouristKiller
-- @version 0.2.0
-- @changelog 
--[[
+ Initial release
]]--

local r = reaper

if not r.SNM_GetIntConfigVar then
    r.ShowMessageBox('The SWS extension must be installed to use this script.', 'Error', 0)
    return
end

local flags = {
    0x4000,  -- Volume
    0x2,     -- Lock
    0x80,    -- Notes
    0x8,     -- FX
    0x20,    -- Mute
    0x800,   -- Item Properties
    0x80000  -- Envelope
}

local itemicons = r.SNM_GetIntConfigVar('itemicons', 0)
local any_visible = false

for _, flag in ipairs(flags) do
    if (itemicons & flag) ~= 0 then
        any_visible = true
        break
    end
end

if any_visible then
    for _, flag in ipairs(flags) do
        itemicons = itemicons & ~flag
    end
    r.TrackCtl_SetToolTip("Buttons: HIDDEN", 800, 0, true)
else
    for _, flag in ipairs(flags) do
        itemicons = itemicons | flag
    end
    r.TrackCtl_SetToolTip("Buttons: VISIBLE", 800, 0, true)
end

r.SNM_SetIntConfigVar('itemicons', itemicons)
r.UpdateArrange()
r.TrackList_AdjustWindows(false)
r.SetCursorContext(1, nil)