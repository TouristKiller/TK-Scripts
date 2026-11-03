-- @noindex
-- Swaps files inside a theme's .ReaperThemeZip, for the parts the settings window
-- lets you choose. Every other file's compressed bytes are copied as they are, so
-- nothing has to be unpacked and no outside program is needed. New files go in
-- uncompressed: they are PNGs, which don't shrink any further.
local Zip = {}

local crc_table
function Zip.crc32(s)
    if not crc_table then
        crc_table = {}
        for i = 0, 255 do
            local c = i
            for _ = 1, 8 do
                c = (c & 1) == 1 and (0xEDB88320 ~ (c >> 1)) or (c >> 1)
            end
            crc_table[i] = c
        end
    end
    local c = 0xFFFFFFFF
    for i = 1, #s do
        c = crc_table[(c ~ s:byte(i)) & 0xFF] ~ (c >> 8)
    end
    return c ~ 0xFFFFFFFF
end

local function read_file(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("a")
    f:close()
    return s
end

-- the entries in the zip's own order, from the central directory at its end
local function read_entries(s)
    local eocd
    for at = #s - 21, math.max(1, #s - 21 - 65535), -1 do
        if s:sub(at, at + 3) == "PK\5\6" then
            eocd = at
            break
        end
    end
    if not eocd then return nil, "not a zip file" end
    local count, _, offset = string.unpack("<I2I4I4", s, eocd + 10)
    if count == 0xFFFF or offset == 0xFFFFFFFF then return nil, "zip too large" end
    local entries, at = {}, offset + 1
    for _ = 1, count do
        if s:sub(at, at + 3) ~= "PK\1\2" then return nil, "damaged zip file" end
        local e = {}
        e.made, e.needed, e.flags, e.method, e.time, e.date, e.crc, e.csize, e.usize = string.unpack("<I2I2I2I2I2I2I4I4I4", s, at + 4)
        local name_len, extra_len, comment_len = string.unpack("<I2I2I2", s, at + 28)
        e.attr = string.unpack("<I4", s, at + 38)
        e.local_at = string.unpack("<I4", s, at + 42) + 1
        e.name = s:sub(at + 46, at + 45 + name_len)
        entries[#entries + 1] = e
        at = at + 46 + name_len + extra_len + comment_len
    end
    return entries
end

local function read_data(s, e)
    if s:sub(e.local_at, e.local_at + 3) ~= "PK\3\4" then return nil end
    local name_len, extra_len = string.unpack("<I2I2", s, e.local_at + 26)
    local start = e.local_at + 30 + name_len + extra_len
    return s:sub(start, start + e.csize - 1)
end

-- the folder the theme's images are in, inside the zip
function Zip.root(path)
    local s = read_file(path)
    local entries = s and read_entries(s)
    for _, e in ipairs(entries or {}) do
        local root = e.name:match("^(.*)/rtconfig%.txt$")
        if root and not root:find("/", 1, true) then return root end
    end
    return nil
end

-- the checksum of one file in the zip, to tell whether it holds the file you expect
function Zip.crc_of(path, name)
    local s = read_file(path)
    local entries = s and read_entries(s)
    for _, e in ipairs(entries or {}) do
        if e.name == name then return e.crc end
    end
    return nil
end

-- whether every file in the zip is in the folder, unchanged
function Zip.same_files(path, folder)
    local s = read_file(path)
    local entries = s and read_entries(s)
    if not entries then return false end
    for _, e in ipairs(entries) do
        local data = read_file(folder .. e.name)
        if not data or Zip.crc32(data) ~= e.crc then return false end
    end
    return true
end

-- Unpacks a zip made without compression into a folder that exists, with its subfolders.
-- Returns true, or nil and what went wrong.
function Zip.extract(path, folder)
    local s = read_file(path)
    if not s then return nil, "can't read " .. path end
    local entries, err = read_entries(s)
    if not entries then return nil, err end
    for _, e in ipairs(entries) do
        if e.method ~= 0 then return nil, "compressed file in " .. path end
        local data = read_data(s, e)
        local f = data and io.open(folder .. e.name, "wb")
        if not f then return nil, "can't write " .. e.name end
        local wrote = f:write(data)
        f:close()
        if not wrote then return nil, "can't write " .. e.name .. " (is the disk full?)" end
    end
    return true
end

-- Written next to the file and swapped in, so REAPER never reads half a file and a
-- full disk leaves the old one alone. Returns true, or nil and what went wrong.
function Zip.save(path, data)
    local tmp, old = path .. ".tmp", path .. ".old"
    local f = io.open(tmp, "wb")
    if not f then return nil, "can't write next to the theme file" end
    local wrote = f:write(data)
    f:close()
    if not wrote then
        os.remove(tmp)
        return nil, "can't write next to the theme file (is the disk full?)"
    end
    os.remove(old)
    local existed = read_file(path) ~= nil
    if existed and not os.rename(path, old) then
        os.remove(tmp)
        return nil, "the theme file is in use"
    end
    if not os.rename(tmp, path) then
        if existed then os.rename(old, path) end
        os.remove(tmp)
        return nil, "the theme file couldn't be replaced"
    end
    os.remove(old)
    return true
end

-- files: { [name in the zip] = contents }. Returns true, or nil and what went wrong.
function Zip.replace(path, files)
    local s = read_file(path)
    if not s then return nil, "can't read the theme file" end
    local entries, err = read_entries(s)
    if not entries then return nil, err end

    local todo = {}
    for name, data in pairs(files) do todo[name] = data end
    local function fresh(e, data)
        e.method, e.flags, e.crc, e.csize, e.usize = 0, e.flags & ~8, Zip.crc32(data), #data, #data
        e.data = data
    end
    for _, e in ipairs(entries) do
        if todo[e.name] then
            fresh(e, todo[e.name])
            todo[e.name] = nil
        else
            e.data = read_data(s, e)
            if not e.data then return nil, "damaged zip file" end
            e.flags = e.flags & ~8      -- the sizes go in the header below
        end
    end
    for name, data in pairs(todo) do
        local e = { name = name, made = 20, needed = 20, flags = 0, time = 0, date = 33, attr = 0, local_at = 0 }
        fresh(e, data)
        entries[#entries + 1] = e
    end

    local out, at, central = {}, 0, {}
    for _, e in ipairs(entries) do
        local head = string.pack("<c4I2I2I2I2I2I4I4I4I2I2", "PK\3\4", e.needed, e.flags, e.method, e.time, e.date,
            e.crc, e.csize, e.usize, #e.name, 0)
        out[#out + 1] = head
        out[#out + 1] = e.name
        out[#out + 1] = e.data
        central[#central + 1] = string.pack("<c4I2I2I2I2I2I2I4I4I4I2I2I2I2I2I4I4", "PK\1\2", e.made, e.needed, e.flags, e.method,
            e.time, e.date, e.crc, e.csize, e.usize, #e.name, 0, 0, 0, 0, e.attr, at) .. e.name
        at = at + #head + #e.name + #e.data
    end
    local directory = table.concat(central)
    out[#out + 1] = directory
    out[#out + 1] = string.pack("<c4I2I2I2I2I4I4I2", "PK\5\6", 0, 0, #entries, #entries, #directory, at, 0)

    return Zip.save(path, table.concat(out))
end

-- REAPER keeps a loaded theme's images until another theme has been loaded. A
-- temporary copy of the theme under another name serves as that other theme, so
-- there is nothing else to see in between. reaper-themeconfig.ini keeps layout
-- settings by theme name, so the copy gets a copy of those too.
local STAND_IN = "TK Theme (reloading)"

local function find_section(s, name)
    local head = "[" .. name .. "]"
    local start
    if s:sub(1, #head) == head then
        start = 1
    else
        local at = s:find("\n" .. head, 1, true)
        if not at then return nil end
        start = at + 1
    end
    return start, s:find("\n[", start, true), #head
end

local function without_section(s, name)
    local start, after = find_section(s, name)
    if not start then return s end
    return s:sub(1, start - 1) .. (after and s:sub(after + 1) or "")
end

-- current: the loaded theme's file. Returns the file to load in between, or nil.
function Zip.make_stand_in(current, config)
    local folder, name = current:match("^(.*[\\/])([^\\/]+)%.ReaperTheme")
    local zip = folder and read_file(folder .. name .. ".ReaperThemeZip")
    if not zip or not Zip.save(folder .. STAND_IN .. ".ReaperThemeZip", zip) then return nil end
    local s = read_file(config)
    local start, after, head = find_section(s or "", name)
    if start then
        local eol = s:find("\r\n", 1, true) and "\r\n" or "\n"
        local body = s:sub(start + head, after and after - 1 or #s):gsub("\r$", "")
        s = without_section(s, STAND_IN)
        if s:sub(-1) ~= "\n" then s = s .. eol end
        Zip.save(config, s .. "[" .. STAND_IN .. "]" .. body .. eol)
    end
    local loose = current:match("%.ReaperTheme$") and read_file(current)
    if not loose then return folder .. STAND_IN .. ".ReaperThemeZip" end
    loose = loose:gsub("ui_img=[^\r\n]*", function() return "ui_img=" .. STAND_IN .. ".ReaperThemeZip" end)
    local path = folder .. STAND_IN .. ".ReaperTheme"
    return Zip.save(path, loose) and path or folder .. STAND_IN .. ".ReaperThemeZip"
end

function Zip.remove_stand_in(current, config)
    local folder = current:match("^(.*[\\/])")
    if not folder then return end
    os.remove(folder .. STAND_IN .. ".ReaperThemeZip")
    os.remove(folder .. STAND_IN .. ".ReaperTheme")
    local s = read_file(config)
    if s and find_section(s, STAND_IN) then Zip.save(config, without_section(s, STAND_IN)) end
end

return Zip
