-- Small OS dialog helpers shared by the Explosion and Builder views.

local r = reaper
local M = {}

local EXT_SECTION = "TK_KIT_MAKER"
local EXT_BASE    = "browse_base_folder"
local EXT_LAST    = "browse_last_"
local EXT_EXPORT  = "last_export_folder"

local function normalize(path)
  path = tostring(path or ""):gsub("\\", "/")
  return (path:gsub("/+$", ""))
end

local function parent_dir(path)
  path = normalize(path)
  return path:match("^(.*)/[^/]+$") or path
end

local function is_dir(path)
  if path == "" then return false end
  if r.file_exists and r.file_exists(path) then return false end
  if r.EnumerateFiles and r.EnumerateFiles(path, 0) ~= nil then
    r.EnumerateFiles(path, -1)
    return true
  end
  if r.EnumerateSubdirectories and r.EnumerateSubdirectories(path, 0) ~= nil then
    r.EnumerateSubdirectories(path, -1)
    return true
  end
  local ok, _, code = os.rename(path, path)
  return ok == true or code == 13
end

-- SHBrowseForFolder only selects the folder it is pointed at, it never expands
-- it. Pointing it at the first subfolder instead makes Windows expand our
-- folder so its contents are visible right away.
local function expand_hint(path)
  if path == "" or not r.EnumerateSubdirectories then return path end
  local sub = r.EnumerateSubdirectories(path, 0)
  r.EnumerateSubdirectories(path, -1)
  if not sub or sub == "" then return path end
  return path .. "/" .. sub
end

function M.get_base_folder()
  return normalize(r.GetExtState(EXT_SECTION, EXT_BASE) or "")
end

function M.set_base_folder(path)
  local norm = normalize(path or "")
  r.SetExtState(EXT_SECTION, EXT_BASE, norm, true)
  return norm
end

-- Where the last export actually wrote, which is not the same question as
-- "where did a browse dialog last open". A destination can be typed straight
-- into the field rather than browsed to, and a batch may be run again days
-- later from a preset that carries its own destination -- so the folder you
-- want to go and look at is the one an export last used, recorded by the export
-- itself. Persisted, because looking at what you made is usually the next
-- session rather than the next minute.
function M.get_last_export_folder()
  return normalize(r.GetExtState(EXT_SECTION, EXT_EXPORT) or "")
end

function M.set_last_export_folder(path)
  local norm = normalize(path or "")
  if norm == "" then return "" end
  r.SetExtState(EXT_SECTION, EXT_EXPORT, norm, true)
  return norm
end

function M.get_last_folder(key)
  if not key or key == "" then key = "default" end
  return normalize(r.GetExtState(EXT_SECTION, EXT_LAST .. key) or "")
end

function M.remember_folder(key, path)
  if key == false then return end
  local norm = normalize(path or "")
  if norm == "" then return end
  if not key or key == "" then key = "default" end
  r.SetExtState(EXT_SECTION, EXT_LAST .. key, norm, true)
  r.SetExtState(EXT_SECTION, EXT_LAST .. "default", norm, true)
end

-- Start folder priority: what the caller passed in -> the configured base
-- folder -> last folder used for this kind of browse -> last folder used
-- anywhere. Pass key = false to skip the "recent" tiers entirely.
--
-- The base folder outranks the recent ones on purpose. Setting one is a
-- standing instruction to start there, and it is worth very little if wherever
-- you last happened to browse quietly overrides it; clearing it puts the recent
-- folders back in charge. A start_folder from the caller still wins, because
-- that is a deliberate "open near THIS" -- relinking a collection that moved,
-- for instance -- and it falls through anyway when the folder is gone.
function M.resolve_start(start_folder, key)
  local candidates = { normalize(start_folder or ""), M.get_base_folder() }
  if key ~= false then
    candidates[#candidates + 1] = M.get_last_folder(key)
    candidates[#candidates + 1] = M.get_last_folder("default")
  end
  for _, cand in ipairs(candidates) do
    if cand ~= "" and is_dir(cand) then return cand end
  end
  for _, cand in ipairs(candidates) do
    if cand ~= "" then return cand end
  end
  return ""
end

-- Opens a native folder picker via js_ReaScriptAPI if installed, otherwise
-- falls back to a plain text input dialog.
function M.browse_folder(title, start_folder, key)
  local start = M.resolve_start(start_folder, key)
  local picked
  if r.JS_Dialog_BrowseForFolder then
    local ok, folder = r.JS_Dialog_BrowseForFolder(title, expand_hint(start))
    if ok and folder and folder ~= "" then picked = normalize(folder) end
  else
    local ok, value = r.GetUserInputs(title, 1, "Folder path:,extrawidth=260", start)
    if ok and value ~= "" then picked = normalize(value) end
  end
  if not picked then return nil end
  M.remember_folder(key, picked)
  return picked
end

-- Opens a native single-file picker via js_ReaScriptAPI if installed,
-- otherwise falls back to a plain text input dialog.
function M.browse_file(title, start_folder, extension_filter, key)
  local hint = normalize(start_folder or "")
  if hint ~= "" and not is_dir(hint) then hint = parent_dir(hint) end
  local start = M.resolve_start(hint, key)
  local picked
  if r.JS_Dialog_BrowseForOpenFiles then
    local ok, path = r.JS_Dialog_BrowseForOpenFiles(title, start, "", extension_filter or "", false)
    if (not ok or not path or path == "") and extension_filter and extension_filter ~= "" then
      ok, path = r.JS_Dialog_BrowseForOpenFiles(title, start, "", "", false)
    end
    if ok and path and path ~= "" then picked = normalize(path) end
  else
    local ok, value = r.GetUserInputs(title, 1, "File path:,extrawidth=260", start)
    if ok and value ~= "" then picked = normalize(value) end
  end
  if not picked then return nil end
  M.remember_folder(key, parent_dir(picked))
  return picked
end

return M
