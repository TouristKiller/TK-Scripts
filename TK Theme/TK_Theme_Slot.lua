-- @description TK Theme Dark: runs the action chosen for a transport button
-- @author TouristKiller
-- @version 0.9.14
-- Library for the scripts in slots/: a theme button holds one fixed action, so
-- buttons that can run the user's choice call those, and they call this.
return function(key)
    local r = reaper
    local chosen = r.GetExtState("TK_Theme_Buttons", key)
    local cmd = tonumber(chosen) or (chosen ~= "" and r.NamedCommandLookup(chosen)) or 0
    if cmd == 0 then
        r.ShowMessageBox(chosen == "" and "No action chosen for this button yet.\n\nChoose one on the page Transport buttons in the theme's settings."
            or ("The action chosen for this button no longer exists:\n" .. chosen), "TK Theme", 0)
        return
    end
    r.Main_OnCommand(cmd, 0)
end
