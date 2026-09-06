local r = reaper

return function(key)
    local queue = r.GetExtState("TK_PROJECT_CLIPS_ACTIONS", "queue")
    local commands = {}
    for command in tostring(queue or ""):gmatch("[^|]+") do commands[#commands + 1] = command end
    while #commands >= 64 do table.remove(commands, 1) end
    commands[#commands + 1] = tostring(r.EnumProjects(-1, "")) .. "," .. key
    r.SetExtState("TK_PROJECT_CLIPS_ACTIONS", "queue", table.concat(commands, "|"), false)
end