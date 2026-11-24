-- @description TK Toolbar Icons: choose style
-- @author TouristKiller
--
-- TK's own toolbar icons (TK_*) in more than one look. They live in REAPER's
-- Data/toolbar_icons, which no theme can override, so each look comes as its own set in
-- Data/TK Toolbar Icons/<style>/, and this script copies the chosen set over the TK_
-- names. Your toolbars keep their icons' names; only the pictures change. A window shows
-- the new pictures the next time it opens.
--
-- Run as an action: a menu to pick the style. Themes load it as a library:
--   TK_TOOLBAR_ICONS_LIB = true
--   local icons = dofile(path)      -- then icons.apply("Bit")

local r = reaper
local M = {}
local SEP = package.config:sub(1, 1)
M.root = r.GetResourcePath() .. "/Data/TK Toolbar Icons"
M.target = r.GetResourcePath() .. "/Data/toolbar_icons"
local SCALES = { "", "150", "200" }
local EXT = "TK_Toolbar_Icons"

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("a")
  f:close()
  return s
end

local function write(path, data)
  local f = io.open(path, "wb")
  if not f then return false end
  f:write(data)
  f:close()
  return true
end

local function join(a, b) return b == "" and a or (a .. "/" .. b) end

-- the styles there are: the folders in Data/TK Toolbar Icons
function M.styles()
  local list, i = {}, 0
  while true do
    local d = r.EnumerateSubdirectories(M.root, i)
    if not d then break end
    list[#list + 1] = d
    i = i + 1
  end
  table.sort(list)
  return list
end

function M.installed() return #M.styles() > 0 end

function M.current() return r.GetExtState(EXT, "style") end

-- is this style what Data/toolbar_icons holds now? (another package, a TK Theme update
-- for one, may have put its own files back since)
function M.in_place(style)
  local dir = join(M.root, style)
  local i = 0
  while true do
    local f = r.EnumerateFiles(dir, i)
    if not f then return true end
    if f:match("^TK_.*%.png$") then
      return read(dir .. "/" .. f) == read(M.target .. "/" .. f)
    end
    i = i + 1
  end
end

-- copy a style over the TK_ icons; returns the number of files written, or nil + why
function M.apply(style, force)
  local dir = join(M.root, style)
  if not r.EnumerateFiles(dir, 0) then return nil, "style not installed: " .. tostring(style) end
  if not force and M.in_place(style) then
    r.SetExtState(EXT, "style", style, true)
    return 0
  end
  local n = 0
  for _, sub in ipairs(SCALES) do
    local from, to = join(dir, sub), join(M.target, sub)
    r.RecursiveCreateDirectory(to, 0)
    local i = 0
    while true do
      local f = r.EnumerateFiles(from, i)
      if not f then break end
      if f:match("^TK_.*%.png$") then
        local data = read(from .. "/" .. f)
        if data and write(to .. "/" .. f, data) then n = n + 1 end
      end
      i = i + 1
    end
  end
  r.SetExtState(EXT, "style", style, true)
  return n
end

if TK_TOOLBAR_ICONS_LIB then return M end

---------------------------------------------------------------- run as an action
local styles = M.styles()
if #styles == 0 then
  r.ShowMessageBox("No icon styles found in\n" .. M.root:gsub("/", SEP) ..
    "\n\nReinstall TK Toolbar Icons through ReaPack.", "TK Toolbar Icons", 0)
  return
end
local cur = M.current()
local items = { "#Toolbar icon style" }
for _, s in ipairs(styles) do items[#items + 1] = (s == cur and "!" or "") .. s end
local x, y = r.GetMousePosition()
gfx.init("TK Toolbar Icons", 0, 0, 0, x, y)
gfx.x, gfx.y = 0, 0
local pick = gfx.showmenu(table.concat(items, "|"))
gfx.quit()
if pick > 1 then
  local style = styles[pick - 1]
  local n, err = M.apply(style, true)
  if not n then
    r.ShowMessageBox(err, "TK Toolbar Icons", 0)
  else
    r.ShowMessageBox(("Toolbar icons: %s (%d files).\nA window shows them the next time it opens.")
      :format(style, n), "TK Toolbar Icons", 0)
  end
end
