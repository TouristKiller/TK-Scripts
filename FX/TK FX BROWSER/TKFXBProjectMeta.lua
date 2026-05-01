-- TKFXBProjectMeta.lua
-- Shared module for project metadata (RPP parsing + sidecar + editor modal + sync)
-- Used by both TK_FX_BROWSER.lua (Standard) and TK_FX_BROWSER Mini.lua (Mini)

local M = {}

local r       = reaper
local ctx_ref = nil
local json    = nil

local sidecar_path     = nil
local project_metadata = {}

local rpp_meta_cache = {}

local STATUS_PRESETS = { "Idea", "Tracking", "Mixing", "Mastering", "Released" }
local PROJECT_TYPE_PRESETS = { "Single", "Album", "EP", "Demo", "Sound Design", "Score", "Other" }

local ID3_KEYS = {
    title    = "TIT2",
    artist   = "TPE1",
    album    = "TALB",
    genre    = "TCON",
    year     = "TYER",
    comment  = "COMM",
}

local edit_state = {
    open       = false,
    pending    = false,
    project    = nil,
    rpp        = nil,
    sidecar    = {},
    music = {
        artist = "", album = "", title = "", genre = "", year = "", comment = "",
    },
    tags_str   = "",
}

local function trim(s)
    if not s then return "" end
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

local function unquote(s)
    if not s then return "" end
    s = trim(s)
    if s:sub(1, 1) == '"' and s:sub(-1) == '"' then
        return s:sub(2, -2)
    end
    return s
end

function M.ParseRPP(path)
    if rpp_meta_cache[path] then return rpp_meta_cache[path] end
    local f = io.open(path, "r")
    if not f then return nil end

    local info = {
        bpm = nil, samplerate = nil, track_count = 0,
        author = "", notes = "",
        timesig_num = nil, timesig_den = nil,
        render_metadata = {},
    }

    local in_notes = false
    local in_render_meta = false
    local notes_lines = {}
    local lines_read = 0

    for line in f:lines() do
        lines_read = lines_read + 1
        if lines_read > 8000 then break end

        if in_notes then
            local stripped = line:match("^%s*(.-)%s*$")
            if stripped == ">" then
                in_notes = false
            else
                local content = line:match("^%s*|(.*)$")
                if content then notes_lines[#notes_lines + 1] = content end
            end
        elseif in_render_meta then
            local stripped = line:match("^%s*(.-)%s*$")
            if stripped == ">" then
                in_render_meta = false
            else
                local kind, key, val = line:match("^%s*(%w+):(%w+)%s+(.*)$")
                if kind and key then
                    if not info.render_metadata[kind] then info.render_metadata[kind] = {} end
                    info.render_metadata[kind][key] = val or ""
                end
            end
        else
            if not info.bpm then
                local b, n, d = line:match("^%s*TEMPO%s+([%d%.]+)%s+(%d+)%s+(%d+)")
                if b then
                    info.bpm = tonumber(b)
                    info.timesig_num = tonumber(n)
                    info.timesig_den = tonumber(d)
                else
                    local b2 = line:match("^%s*TEMPO%s+([%d%.]+)")
                    if b2 then info.bpm = tonumber(b2) end
                end
            end
            if not info.samplerate then
                local sr = line:match("^%s*SAMPLERATE%s+(%d+)")
                if sr then info.samplerate = tonumber(sr) end
            end
            if line:match("^%s*<TRACK") then
                info.track_count = info.track_count + 1
            end
            local a = line:match("^%s*AUTHOR%s+(.+)$")
            if a then info.author = unquote(a) end
            if line:match("^%s*<NOTES") then
                in_notes = true
            elseif line:match("^%s*<RENDER_METADATA") then
                in_render_meta = true
            end
        end
    end

    f:close()
    info.notes = table.concat(notes_lines, "\n")
    rpp_meta_cache[path] = info
    return info
end

function M.InvalidateCache(path)
    if path then rpp_meta_cache[path] = nil else rpp_meta_cache = {} end
end

local function load_sidecar()
    project_metadata = {}
    if not sidecar_path then return end
    local f = io.open(sidecar_path, "r")
    if not f then return end
    local content = f:read("*a")
    f:close()
    if not content or content == "" then return end
    local ok, data = pcall(json.decode, content)
    if ok and type(data) == "table" then project_metadata = data end
end

local function save_sidecar()
    if not sidecar_path or not json then return end
    local f = io.open(sidecar_path, "w")
    if f then
        f:write(json.encode(project_metadata))
        f:close()
    end
end

function M.GetSidecar(projPath)
    return project_metadata[projPath] or {}
end

function M.HasSidecar(projPath)
    local m = project_metadata[projPath]
    if not m then return end
    for _ in pairs(m) do return true end
    return false
end

function M.GetDisplay(projPath, rpp)
    local sc = project_metadata[projPath] or {}
    local rm = (rpp and rpp.render_metadata and rpp.render_metadata.ID3) or {}
    local function pick(over, id3key)
        if over and over ~= "" then return over end
        return rm[id3key] or ""
    end
    return {
        artist  = pick(sc.artistOverride,  ID3_KEYS.artist),
        album   = pick(sc.albumOverride,   ID3_KEYS.album),
        title   = pick(sc.titleOverride,   ID3_KEYS.title),
        genre   = pick(sc.genreOverride,   ID3_KEYS.genre),
        year    = pick(sc.yearOverride,    ID3_KEYS.year),
        comment = pick(sc.commentOverride, ID3_KEYS.comment),
        status  = sc.status or "",
        rating  = tonumber(sc.rating) or 0,
        client  = sc.client or "",
        project_type = sc.project_type or "",
        deadline = sc.deadline or "",
        tags    = sc.tags or {},
    }
end

local function find_active_project(path)
    local i = 0
    while true do
        local proj, projfn = r.EnumProjects(i)
        if not proj then return nil end
        if projfn == path then return proj end
        i = i + 1
    end
end

function M.IsActive(path)
    return find_active_project(path) ~= nil
end

function M.OpenEditor(project)
    if not project or not project.path then return end
    local rpp = M.ParseRPP(project.path) or {}
    local sc  = M.GetSidecar(project.path)
    local rm  = (rpp.render_metadata and rpp.render_metadata.ID3) or {}

    edit_state.project = project
    edit_state.rpp     = rpp
    edit_state.sidecar = {
        status       = sc.status or "",
        rating       = tonumber(sc.rating) or 0,
        client       = sc.client or "",
        project_type = sc.project_type or "",
        deadline     = sc.deadline or "",
        tags         = sc.tags or {},
    }
    edit_state.music = {
        artist  = sc.artistOverride  or rm[ID3_KEYS.artist]  or "",
        album   = sc.albumOverride   or rm[ID3_KEYS.album]   or "",
        title   = sc.titleOverride   or rm[ID3_KEYS.title]   or "",
        genre   = sc.genreOverride   or rm[ID3_KEYS.genre]   or "",
        year    = sc.yearOverride    or rm[ID3_KEYS.year]    or "",
        comment = sc.commentOverride or rm[ID3_KEYS.comment] or "",
    }
    edit_state.tags_str = table.concat(edit_state.sidecar.tags or {}, ", ")
    edit_state.pending = true
end

local function save_edit()
    local p = edit_state.project
    if not p then return end
    local rm = (edit_state.rpp and edit_state.rpp.render_metadata and edit_state.rpp.render_metadata.ID3) or {}

    local entry = project_metadata[p.path] or {}

    local function setOverride(key, val, autoVal)
        if val == "" or val == autoVal then
            entry[key] = nil
        else
            entry[key] = val
        end
    end
    setOverride("artistOverride",  edit_state.music.artist,  rm[ID3_KEYS.artist]  or "")
    setOverride("albumOverride",   edit_state.music.album,   rm[ID3_KEYS.album]   or "")
    setOverride("titleOverride",   edit_state.music.title,   rm[ID3_KEYS.title]   or "")
    setOverride("genreOverride",   edit_state.music.genre,   rm[ID3_KEYS.genre]   or "")
    setOverride("yearOverride",    edit_state.music.year,    rm[ID3_KEYS.year]    or "")
    setOverride("commentOverride", edit_state.music.comment, rm[ID3_KEYS.comment] or "")

    local sc = edit_state.sidecar
    entry.status       = (sc.status       ~= "" and sc.status)       or nil
    entry.rating       = (sc.rating and sc.rating > 0) and sc.rating or nil
    entry.client       = (sc.client       ~= "" and sc.client)       or nil
    entry.project_type = (sc.project_type ~= "" and sc.project_type) or nil
    entry.deadline     = (sc.deadline     ~= "" and sc.deadline)     or nil

    local tags = {}
    for tag in (edit_state.tags_str .. ","):gmatch("([^,]*),") do
        local t = trim(tag)
        if t ~= "" then tags[#tags + 1] = t end
    end
    entry.tags = (#tags > 0) and tags or nil

    local has_any = false
    for _ in pairs(entry) do has_any = true; break end
    project_metadata[p.path] = has_any and entry or nil
    save_sidecar()
end

function M.SyncToRPP()
    local p = edit_state.project
    if not p then return false, "No project" end
    local proj = find_active_project(p.path)
    if not proj then return false, "Project is not currently open in REAPER" end

    local function setMeta(id3, val)
        r.GetSetProjectInfo_String(proj, "RENDER_METADATA", "ID3:" .. id3 .. "=" .. (val or ""), true)
    end
    setMeta(ID3_KEYS.artist,  edit_state.music.artist)
    setMeta(ID3_KEYS.album,   edit_state.music.album)
    setMeta(ID3_KEYS.title,   edit_state.music.title)
    setMeta(ID3_KEYS.genre,   edit_state.music.genre)
    setMeta(ID3_KEYS.year,    edit_state.music.year)
    setMeta(ID3_KEYS.comment, edit_state.music.comment)

    r.Main_OnCommandEx(40026, 0, proj)
    M.InvalidateCache(p.path)
    return true
end

local function combo(label, current, options, allow_empty)
    local changed = false
    if r.ImGui_BeginCombo(ctx_ref, label, current ~= "" and current or "(none)") then
        if allow_empty then
            if r.ImGui_Selectable(ctx_ref, "(none)", current == "") then
                current = ""; changed = true
            end
        end
        for _, opt in ipairs(options) do
            if r.ImGui_Selectable(ctx_ref, opt, current == opt) then
                current = opt; changed = true
            end
        end
        r.ImGui_EndCombo(ctx_ref)
    end
    return changed, current
end

local function rating_widget(label, value)
    r.ImGui_Text(ctx_ref, label)
    r.ImGui_SameLine(ctx_ref, 110)
    local changed = false
    for i = 1, 5 do
        local star = (i <= value) and "*" or "-"
        if r.ImGui_SmallButton(ctx_ref, star .. "##rate" .. i) then
            value = (value == i) and 0 or i
            changed = true
        end
        if i < 5 then r.ImGui_SameLine(ctx_ref, 0, 2) end
    end
    return changed, value
end

local function field_input(label, value, hint)
    r.ImGui_AlignTextToFramePadding(ctx_ref)
    r.ImGui_Text(ctx_ref, label)
    r.ImGui_SameLine(ctx_ref, 110)
    r.ImGui_SetNextItemWidth(ctx_ref, -1)
    local changed, new = r.ImGui_InputText(ctx_ref, "##" .. label, value)
    if hint and hint ~= "" and r.ImGui_IsItemHovered(ctx_ref) then
        r.ImGui_SetTooltip(ctx_ref, "RPP value: " .. hint)
    end
    return changed, new
end

function M.DrawEditor()
    if edit_state.pending then
        r.ImGui_OpenPopup(ctx_ref, "Edit Project Metadata##tk_meta")
        edit_state.pending = false
        edit_state.open = true
    end

    r.ImGui_SetNextWindowSize(ctx_ref, 520, 620, r.ImGui_Cond_Appearing())
    local visible, open = r.ImGui_BeginPopupModal(ctx_ref, "Edit Project Metadata##tk_meta", true, 0)
    if not visible then
        edit_state.open = open
        return
    end

    local p = edit_state.project
    if not p then
        r.ImGui_EndPopup(ctx_ref)
        return
    end

    r.ImGui_PushStyleColor(ctx_ref, r.ImGui_Col_Text(), 0x7AA2F7FF)
    r.ImGui_Text(ctx_ref, p.name or p.path)
    r.ImGui_PopStyleColor(ctx_ref, 1)

    local active = find_active_project(p.path) ~= nil
    r.ImGui_PushStyleColor(ctx_ref, r.ImGui_Col_Text(), 0x999999FF)
    r.ImGui_Text(ctx_ref, active and "[Active in REAPER]" or "[Not loaded]")
    r.ImGui_PopStyleColor(ctx_ref, 1)
    r.ImGui_Separator(ctx_ref)
    r.ImGui_Spacing(ctx_ref)

    if r.ImGui_BeginChild(ctx_ref, "##meta_scroll", -1, -50) then
        r.ImGui_PushStyleColor(ctx_ref, r.ImGui_Col_Text(), 0x7AA2F7FF)
        r.ImGui_Text(ctx_ref, "Music Metadata (RPP RENDER_METADATA)")
        r.ImGui_PopStyleColor(ctx_ref, 1)
        r.ImGui_Spacing(ctx_ref)

        local rm = (edit_state.rpp and edit_state.rpp.render_metadata and edit_state.rpp.render_metadata.ID3) or {}
        local m = edit_state.music
        local c
        c, m.artist  = field_input("Artist:",  m.artist,  rm[ID3_KEYS.artist])
        c, m.album   = field_input("Album:",   m.album,   rm[ID3_KEYS.album])
        c, m.title   = field_input("Title:",   m.title,   rm[ID3_KEYS.title])
        c, m.genre   = field_input("Genre:",   m.genre,   rm[ID3_KEYS.genre])
        c, m.year    = field_input("Year:",    m.year,    rm[ID3_KEYS.year])
        c, m.comment = field_input("Comment:", m.comment, rm[ID3_KEYS.comment])

        r.ImGui_Spacing(ctx_ref)
        r.ImGui_Separator(ctx_ref)
        r.ImGui_Spacing(ctx_ref)

        r.ImGui_PushStyleColor(ctx_ref, r.ImGui_Col_Text(), 0x7AA2F7FF)
        r.ImGui_Text(ctx_ref, "Project Organization (sidecar)")
        r.ImGui_PopStyleColor(ctx_ref, 1)
        r.ImGui_Spacing(ctx_ref)

        local sc = edit_state.sidecar
        r.ImGui_AlignTextToFramePadding(ctx_ref)
        r.ImGui_Text(ctx_ref, "Status:")
        r.ImGui_SameLine(ctx_ref, 110)
        r.ImGui_SetNextItemWidth(ctx_ref, -1)
        c, sc.status = combo("##status", sc.status, STATUS_PRESETS, true)

        local rc, rv = rating_widget("Rating:", sc.rating or 0)
        if rc then sc.rating = rv end

        c, sc.client = field_input("Client:", sc.client, nil)

        r.ImGui_AlignTextToFramePadding(ctx_ref)
        r.ImGui_Text(ctx_ref, "Type:")
        r.ImGui_SameLine(ctx_ref, 110)
        r.ImGui_SetNextItemWidth(ctx_ref, -1)
        c, sc.project_type = combo("##ptype", sc.project_type, PROJECT_TYPE_PRESETS, true)

        c, sc.deadline = field_input("Deadline:", sc.deadline, nil)

        r.ImGui_AlignTextToFramePadding(ctx_ref)
        r.ImGui_Text(ctx_ref, "Tags:")
        r.ImGui_SameLine(ctx_ref, 110)
        r.ImGui_SetNextItemWidth(ctx_ref, -1)
        c, edit_state.tags_str = r.ImGui_InputText(ctx_ref, "##tags", edit_state.tags_str)
        if r.ImGui_IsItemHovered(ctx_ref) then
            r.ImGui_SetTooltip(ctx_ref, "Comma-separated")
        end

        r.ImGui_EndChild(ctx_ref)
    end

    r.ImGui_Separator(ctx_ref)

    if r.ImGui_Button(ctx_ref, "Save", 80, 0) then
        save_edit()
        r.ImGui_CloseCurrentPopup(ctx_ref)
    end
    r.ImGui_SameLine(ctx_ref)

    if not active then r.ImGui_BeginDisabled(ctx_ref) end
    if r.ImGui_Button(ctx_ref, "Save + Sync to RPP", 160, 0) then
        save_edit()
        local ok, err = M.SyncToRPP()
        if not ok then r.ShowMessageBox(err or "Sync failed", "TK FX Browser", 0) end
        r.ImGui_CloseCurrentPopup(ctx_ref)
    end
    if not active then r.ImGui_EndDisabled(ctx_ref) end
    if active and r.ImGui_IsItemHovered(ctx_ref) then
        r.ImGui_SetTooltip(ctx_ref, "Save sidecar AND write Music Metadata to project's RPP RENDER_METADATA")
    elseif (not active) and r.ImGui_IsItemHovered(ctx_ref) then
        r.ImGui_SetTooltip(ctx_ref, "Open this project in REAPER to enable sync")
    end

    r.ImGui_SameLine(ctx_ref)
    if r.ImGui_Button(ctx_ref, "Cancel", 80, 0) then
        r.ImGui_CloseCurrentPopup(ctx_ref)
    end

    r.ImGui_EndPopup(ctx_ref)
end

function M.Init(deps)
    ctx_ref       = deps.ctx
    json          = deps.json
    sidecar_path  = deps.sidecar_path
    load_sidecar()
end

function M.SetContext(ctx)
    ctx_ref = ctx
end

function M.GetStatusPresets()       return STATUS_PRESETS end
function M.GetProjectTypePresets()  return PROJECT_TYPE_PRESETS end

return M
