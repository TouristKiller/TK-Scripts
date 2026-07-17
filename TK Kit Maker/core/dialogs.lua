-- Small OS dialog helpers shared by the Explosion and Builder views.

local r = reaper
local M = {}

local function normalize(path)
  path = tostring(path or ""):gsub("\\", "/")
  return (path:gsub("/+$", ""))
end

-- Opens a native folder picker via js_ReaScriptAPI if installed, otherwise
-- falls back to a plain text input dialog.
function M.browse_folder(title, start_folder)
  start_folder = normalize(start_folder or "")
  if r.JS_Dialog_BrowseForFolder then
    local ok, folder = r.JS_Dialog_BrowseForFolder(title, start_folder)
    if ok and folder and folder ~= "" then return normalize(folder) end
    return nil
  end
  local ok, value = r.GetUserInputs(title, 1, "Folder path:,extrawidth=260", start_folder)
  if not ok or value == "" then return nil end
  return normalize(value)
end

-- Opens a native single-file picker via js_ReaScriptAPI if installed,
-- otherwise falls back to a plain text input dialog.
function M.browse_file(title, start_folder, extension_filter)
  start_folder = normalize(start_folder or "")
  if r.JS_Dialog_BrowseForOpenFiles then
    local ok, path = r.JS_Dialog_BrowseForOpenFiles(title, start_folder, "", extension_filter or "", false)
    if (not ok or not path or path == "") and extension_filter and extension_filter ~= "" then
      ok, path = r.JS_Dialog_BrowseForOpenFiles(title, start_folder, "", "", false)
    end
    if ok and path and path ~= "" then return normalize(path) end
    return nil
  end
  local ok, value = r.GetUserInputs(title, 1, "File path:,extrawidth=260", start_folder)
  if not ok or value == "" then return nil end
  return normalize(value)
end

return M
