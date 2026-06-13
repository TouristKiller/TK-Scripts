local r = reaper
local Theme = require("core.theme")
local UI = require("core.ui")
local UIScale = require("core.ui_scale")

local M = {
  id = "arrange_bg_presets",
  title = "Arrange BG",
  icon = "ABP",
  version = "0.1.0"
}

local BACKGROUND_FIELDS = {
  { key = "col_arrangebg", label = "Arrange background" },
  { key = "col_tr1_bg", label = "Track background 1" },
  { key = "col_tr2_bg", label = "Track background 2" },
  { key = "selcol_tr1_bg", label = "Selected track 1" },
  { key = "selcol_tr2_bg", label = "Selected track 2" }
}

local GRID_FIELDS = {
  { key = "col_gridlines2", label = "Grid line (measure)" },
  { key = "col_gridlines3", label = "Grid line (beat)" },
  { key = "col_gridlines", label = "Grid line (sub)" }
}

local DIVIDER_FIELDS = {
  { key = "col_tr1_divline", label = "Track divider line 1" },
  { key = "col_tr2_divline", label = "Track divider line 2" }
}

local function all_color_fields()
  local fields = {}
  for _, field in ipairs(BACKGROUND_FIELDS) do fields[#fields + 1] = field end
  for _, field in ipairs(GRID_FIELDS) do fields[#fields + 1] = field end
  for _, field in ipairs(DIVIDER_FIELDS) do fields[#fields + 1] = field end
  return fields
end

local COLOR_FIELDS = all_color_fields()

local COLOR_FIELD_SET = {}
for _, field in ipairs(COLOR_FIELDS) do COLOR_FIELD_SET[field.key] = true end

local state = {
  message = nil,
  message_severity = "info",
  picker_open = false
}

local function color_to_hex(native)
  if not native or native < 0 then return "#000000" end
  local rr, gg, bb = r.ColorFromNative(native)
  return string.format("#%02X%02X%02X", rr or 0, gg or 0, bb or 0)
end

local function hex_to_native(hex)
  local clean = tostring(hex or ""):gsub("%s+", ""):upper()
  if clean:sub(1, 1) == "#" then clean = clean:sub(2) end
  if not clean:match("^[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]$") then return nil end
  local rr = tonumber(clean:sub(1, 2), 16)
  local gg = tonumber(clean:sub(3, 4), 16)
  local bb = tonumber(clean:sub(5, 6), 16)
  return r.ColorToNative(rr, gg, bb)
end

local function hex_to_imgui_color(hex)
  local clean = tostring(hex or ""):gsub("%s+", ""):upper():gsub("#", "")
  if not clean:match("^[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]$") then clean = "000000" end
  return tonumber(clean .. "FF", 16) or 0x000000FF
end

local function imgui_color_to_hex(value)
  local color = math.floor(tonumber(value) or 0)
  local rr = math.floor(color / 0x1000000) % 0x100
  local gg = math.floor(color / 0x10000) % 0x100
  local bb = math.floor(color / 0x100) % 0x100
  return string.format("#%02X%02X%02X", rr, gg, bb)
end

local function current_colors()
  local colors = {}
  for _, field in ipairs(COLOR_FIELDS) do
    colors[field.key] = color_to_hex(r.GetThemeColor(field.key, 0))
  end
  return colors
end

local function default_presets()
  return {
    {
      name = "Light",
      apply_tracks = true,
      apply_grid = true,
      colors = {
        col_arrangebg = "#DCDCDC",
        col_tr1_bg = "#D2D2D2",
        col_tr2_bg = "#C8C8C8",
        col_tr1_divline = "#B4B4B4",
        col_tr2_divline = "#B4B4B4",
        selcol_tr1_bg = "#BEBEBE",
        selcol_tr2_bg = "#B4B4B4",
        col_gridlines = "#AAAAAA",
        col_gridlines2 = "#888888",
        col_gridlines3 = "#666666"
      }
    },
    {
      name = "Dark",
      apply_tracks = true,
      apply_grid = true,
      colors = {
        col_arrangebg = "#2E2E2E",
        col_tr1_bg = "#353535",
        col_tr2_bg = "#2A2A2A",
        col_tr1_divline = "#3D3D3D",
        col_tr2_divline = "#3D3D3D",
        selcol_tr1_bg = "#3E3E3E",
        selcol_tr2_bg = "#454545",
        col_gridlines = "#4A4A4A",
        col_gridlines2 = "#6E6E6E",
        col_gridlines3 = "#909090"
      }
    },
    {
      name = "Arrange only",
      apply_tracks = false,
      apply_grid = false,
      colors = {
        col_arrangebg = "#3A3A3A",
        col_tr1_bg = "#353535",
        col_tr2_bg = "#2A2A2A",
        col_tr1_divline = "#3D3D3D",
        col_tr2_divline = "#3D3D3D",
        selcol_tr1_bg = "#3E3E3E",
        selcol_tr2_bg = "#454545",
        col_gridlines = "#4A4A4A",
        col_gridlines2 = "#6E6E6E",
        col_gridlines3 = "#909090"
      }
    }
  }
end

local function ensure_preset(presets, index)
  local preset = presets[index]
  if type(preset) ~= "table" then
    preset = { name = "Preset " .. index, apply_tracks = true, apply_grid = true, colors = current_colors() }
    presets[index] = preset
  end
  if type(preset.colors) ~= "table" then preset.colors = current_colors() end
  if preset.apply_tracks == nil then preset.apply_tracks = true end
  if preset.apply_grid == nil then preset.apply_grid = true end
  if not preset.name or preset.name == "" then preset.name = "Preset " .. index end
  local fallback = current_colors()
  for _, field in ipairs(COLOR_FIELDS) do
    if not preset.colors[field.key] or not hex_to_native(preset.colors[field.key]) then
      preset.colors[field.key] = fallback[field.key] or "#000000"
    end
  end
  return preset
end

local function ensure_settings(app)
  local settings = app.settings.arrange_bg_presets
  if type(settings) ~= "table" then
    settings = { presets = default_presets(), selected = 1, toggle_a = 1, toggle_b = 2, last_toggle = 2 }
    app.settings.arrange_bg_presets = settings
  end
  if type(settings.presets) ~= "table" or #settings.presets == 0 then settings.presets = default_presets() end
  for index = 1, #settings.presets do ensure_preset(settings.presets, index) end
  local count = #settings.presets
  settings.selected = math.max(1, math.min(tonumber(settings.selected) or 1, count))
  settings.toggle_a = math.max(1, math.min(tonumber(settings.toggle_a) or 1, count))
  settings.toggle_b = math.max(1, math.min(tonumber(settings.toggle_b) or math.min(2, count), count))
  settings.last_toggle = math.max(1, math.min(tonumber(settings.last_toggle) or settings.toggle_b, count))
  if type(settings.favorite_themes) ~= "table" then settings.favorite_themes = {} end
  settings.favorite_selected = math.max(0, math.min(tonumber(settings.favorite_selected) or 0, #settings.favorite_themes))
  if #settings.favorite_themes > 0 and settings.favorite_selected == 0 then settings.favorite_selected = 1 end
  return settings
end

local function persist(app)
  if app.save_settings then app.save_settings() end
end

local function set_message(text, severity)
  state.message = text
  state.message_severity = severity or "info"
end

local function run_action(label, fn)
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local ok, result = pcall(fn)
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock(label, -1)
  return ok and result
end

local function apply_preset(preset)
  if not preset or type(preset.colors) ~= "table" then return false end
  local arrange_native = hex_to_native(preset.colors.col_arrangebg)
  if not arrange_native then return false end
  local divider_natives = {}
  r.SetThemeColor("col_arrangebg", arrange_native, 0)
  if preset.apply_tracks then
    for i = 2, #BACKGROUND_FIELDS do
      local key = BACKGROUND_FIELDS[i].key
      local native = hex_to_native(preset.colors[key])
      if native then r.SetThemeColor(key, native, 0) end
    end
    for _, field in ipairs(DIVIDER_FIELDS) do
      local native = hex_to_native(preset.colors[field.key])
      if native then divider_natives[#divider_natives + 1] = { key = field.key, native = native } end
    end
  end
  if preset.apply_grid then
    for _, field in ipairs(GRID_FIELDS) do
      local native = hex_to_native(preset.colors[field.key])
      if native then r.SetThemeColor(field.key, native, 0) end
    end
  end
  r.TrackList_AdjustWindows(false)
  r.UpdateTimeline()
  r.UpdateArrange()
  if preset.apply_tracks and #divider_natives > 0 then
    for _, entry in ipairs(divider_natives) do r.SetThemeColor(entry.key, entry.native, 0) end
  end
  r.ThemeLayout_RefreshAll()
  r.TrackList_AdjustWindows(false)
  r.UpdateTimeline()
  r.UpdateArrange()
  return true
end

local function reset_theme_colors()
  for _, field in ipairs(COLOR_FIELDS) do r.SetThemeColor(field.key, -1, 0) end
  r.UpdateArrange()
  return true
end

local GRID_DM_MAP = {
  col_gridlines = "col_gridlines1dm",
  col_gridlines2 = "col_gridlines2dm",
  col_gridlines3 = "col_gridlines3dm"
}

local GRID_DM_KEYS = { col_gridlines1dm = true, col_gridlines2dm = true, col_gridlines3dm = true }

local function dm_with_full_alpha(value)
  local v = math.floor(tonumber(value) or 0)
  local mode = v & 0xFF
  return ((0x0200 + 256) << 8) | mode
end

local function read_all_text(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local text = file:read("*a")
  file:close()
  return text
end

local function file_exists(path)
  local file = io.open(path, "rb")
  if file then file:close() return true end
  return false
end

local function path_sep()
  return package.config:sub(1, 1)
end

local function split_path(path)
  local dir, name, ext = tostring(path or ""):match("^(.*)[/\\]([^/\\]+)(%.[^.]+)$")
  if not dir then return nil end
  return dir, name, ext
end

local function extract_ini_section(text, section)
  local out = {}
  local in_section = false
  for line in (tostring(text or "") .. "\n"):gmatch("([^\r\n]*)\r?\n") do
    local header = line:match("^%[(.-)%]%s*$")
    if header then
      in_section = header:lower() == section:lower()
    elseif in_section then
      out[#out + 1] = line
    end
  end
  return out
end

local function ini_value(text, key)
  for line in (tostring(text or "") .. "\n"):gmatch("([^\r\n]*)\r?\n") do
    local value = line:match("^" .. key .. "%s*=%s*(.-)%s*$")
    if value then return value end
  end
  return nil
end

local function find_file_recursive(root, target, depth)
  if not r.EnumerateFiles or not r.EnumerateSubdirectories then return nil end
  local index = 0
  while true do
    local name = r.EnumerateFiles(root, index)
    if not name then break end
    if name:lower() == target:lower() then return root .. path_sep() .. name end
    index = index + 1
  end
  if (depth or 0) <= 0 then return nil end
  index = 0
  while true do
    local sub = r.EnumerateSubdirectories(root, index)
    if not sub then break end
    local found = find_file_recursive(root .. path_sep() .. sub, target, depth - 1)
    if found then return found end
    index = index + 1
  end
  return nil
end

local function powershell_exe()
  local windir = os.getenv("WINDIR") or os.getenv("SystemRoot") or "C:\\Windows"
  local full = windir .. "\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"
  if file_exists(full) then return full end
  return "powershell.exe"
end

local function refresh_theme_ui()
  if r.ThemeLayout_RefreshAll then r.ThemeLayout_RefreshAll() end
  if r.TrackList_AdjustWindows then r.TrackList_AdjustWindows(false) end
  if r.UpdateTimeline then r.UpdateTimeline() end
  if r.UpdateArrange then r.UpdateArrange() end
end

local function extract_zip_theme_master(zip_path)
  if not r.ExecProcess or path_sep() ~= "\\" then return nil end
  local resource = r.GetResourcePath and r.GetResourcePath() or ""
  if resource == "" then return nil end
  local base = resource .. path_sep() .. "ColorThemes" .. path_sep()
  local out_path = base .. "_tk_abp_master.tmp"
  local ps_path = base .. "_tk_abp_extract.ps1"
  local script = table.concat({
    "Add-Type -AssemblyName System.IO.Compression.FileSystem",
    "$zip = '" .. zip_path:gsub("'", "''") .. "'",
    "$out = '" .. out_path:gsub("'", "''") .. "'",
    "$a = [System.IO.Compression.ZipFile]::OpenRead($zip)",
    "$e = $a.Entries | Where-Object { $_.Name -like '*.ReaperTheme' } | Select-Object -First 1",
    "if ($e) { [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $out, $true) }",
    "$a.Dispose()"
  }, "\r\n")
  os.remove(out_path)
  local pf = io.open(ps_path, "wb")
  if not pf then return nil end
  pf:write(script)
  pf:close()
  local cmd = '"' .. powershell_exe() .. '" -NoProfile -ExecutionPolicy Bypass -File "' .. ps_path .. '"'
  r.ExecProcess(cmd, 20000)
  local text = read_all_text(out_path)
  os.remove(out_path)
  os.remove(ps_path)
  if text and text ~= "" then return text end
  return nil
end

local function resolve_reapertheme_path(app)
  local theme_path = r.GetLastColorThemeFile and r.GetLastColorThemeFile() or ""
  if theme_path and theme_path:lower():match("%.reapertheme$") and file_exists(theme_path) then
    return theme_path, false
  end

  local resource = r.GetResourcePath and r.GetResourcePath() or ""
  if resource == "" then return nil end
  local ini_text = read_all_text(resource .. path_sep() .. "reaper.ini")
  if not ini_text then return nil, nil, "Could not read reaper.ini" end
  local section = extract_ini_section(ini_text, "color theme")
  if #section == 0 then return nil, nil, "No [color theme] snapshot found in reaper.ini" end

  local zip_path
  if theme_path and theme_path:lower():match("%.reaperthemezip$") and file_exists(theme_path) then
    zip_path = theme_path
  else
    local zip_name = ini_value(ini_text, "ui_img")
    if zip_name and zip_name ~= "" then
      zip_path = find_file_recursive(resource .. path_sep() .. "ColorThemes", zip_name, 2)
    end
  end

  local target_path
  if zip_path then
    local dir, name = split_path(zip_path)
    if dir and name then target_path = dir .. path_sep() .. name .. ".ReaperTheme" end
  end
  if not target_path then
    local base = "TK Custom Theme"
    local zip_name = ini_value(ini_text, "ui_img")
    if zip_name and zip_name ~= "" then base = zip_name:gsub("%.[Rr]eaper[Tt]heme[Zz]ip$", "") end
    target_path = resource .. path_sep() .. "ColorThemes" .. path_sep() .. base .. ".ReaperTheme"
  end

  local master_text = zip_path and extract_zip_theme_master(zip_path) or nil
  if zip_path and not master_text then
    return nil, nil, "Could not read the theme inside the .ReaperThemeZip; aborted to avoid corrupting the theme"
  end
  local color_section = section
  local reaper_section = extract_ini_section(ini_text, "REAPER")
  if master_text then
    local master_colors = extract_ini_section(master_text, "color theme")
    if #master_colors > 0 then color_section = master_colors end
    local master_reaper = extract_ini_section(master_text, "REAPER")
    if #master_reaper > 0 then reaper_section = master_reaper end
  end

  local refreshed = {}
  for _, line in ipairs(color_section) do
    local key = line:match("^%s*([%w_]+)%s*=%s*-?%d+%s*$")
    if key and COLOR_FIELD_SET[key] then
      local live = r.GetThemeColor(key, 0)
      if live and live >= 0 then
        refreshed[#refreshed + 1] = key .. "=" .. tostring(live)
      else
        refreshed[#refreshed + 1] = line
      end
    else
      refreshed[#refreshed + 1] = line
    end
  end

  local zip_base
  if zip_path then zip_base = tostring(zip_path):match("([^/\\]+)$") end

  local theme_keys = {}
  local ui_img_set = false
  for _, line in ipairs(reaper_section) do
    local key = line:match("^%s*([%w_]+)%s*=")
    if key == "ui_img" then
      if zip_base then
        theme_keys[#theme_keys + 1] = "ui_img=" .. zip_base
      else
        theme_keys[#theme_keys + 1] = line
      end
      ui_img_set = true
    elseif key and key:match("_font%d*$") then
      theme_keys[#theme_keys + 1] = line
    end
  end
  if not ui_img_set and zip_base then
    table.insert(theme_keys, 1, "ui_img=" .. zip_base)
  end

  local content = "[color theme]\n" .. table.concat(refreshed, "\n") .. "\n"
  if #theme_keys > 0 then
    content = content .. "\n[REAPER]\n" .. table.concat(theme_keys, "\n") .. "\n"
  end
  local file = io.open(target_path, "wb")
  if not file then return nil, nil, "Could not write the new .ReaperTheme" end
  file:write(content)
  file:close()
  return target_path, true, nil, zip_path
end

local function grid_full_alpha(app)
  if not r.OpenColorThemeFile or not r.GetLastColorThemeFile then
    set_message("OpenColorThemeFile is not available in this REAPER version", "warning")
    return
  end
  local theme_path, created, err, source_zip = resolve_reapertheme_path(app)
  if not theme_path then
    set_message(err or "Could not resolve a .ReaperTheme for the active theme", "warning")
    return
  end
  local text = read_all_text(theme_path)
  if not text then
    set_message("Could not read the theme file", "warning")
    return
  end

  local backup_path = theme_path .. ".tkbak"
  local source_path = theme_path .. ".tksrc"
  if created and source_zip and source_zip ~= "" then
    local src = io.open(source_path, "wb")
    if src then
      src:write(source_zip)
      src:close()
    end
  elseif not file_exists(source_path) and not file_exists(backup_path) then
    local backup = io.open(backup_path, "wb")
    if backup then
      backup:write(text)
      backup:close()
    end
  end

  local crlf = text:find("\r\n", 1, true) ~= nil
  local newline = crlf and "\r\n" or "\n"
  local trailing = text:match("(\r?\n)$") and newline or ""

  local existing = {}
  for line in (text .. "\n"):gmatch("([^\r\n]*)\r?\n") do
    local key = line:match("^%s*([%w_]+)%s*=")
    if key and GRID_DM_KEYS[key] then existing[key] = true end
  end

  local out = {}
  local changed = false
  for line in (text .. "\n"):gmatch("([^\r\n]*)\r?\n") do
    local key = line:match("^%s*([%w_]+)%s*=")
    if key and GRID_DM_KEYS[key] then
      local cur = tonumber(line:match("=%s*(-?%d+)")) or 0
      local full = dm_with_full_alpha(cur)
      out[#out + 1] = key .. "=" .. tostring(full)
      if full ~= cur then changed = true end
    else
      out[#out + 1] = line
      local dm_key = key and GRID_DM_MAP[key]
      if dm_key and not existing[dm_key] then
        out[#out + 1] = dm_key .. "=" .. tostring(dm_with_full_alpha(0))
        existing[dm_key] = true
        changed = true
      end
    end
  end

  if out[#out] == "" then out[#out] = nil end

  local file = io.open(theme_path, "wb")
  if not file then
    set_message("Could not write the theme file", "warning")
    return
  end
  file:write(table.concat(out, newline) .. trailing)
  file:close()
  r.OpenColorThemeFile(theme_path)
  refresh_theme_ui()
  if created then
    local _, name = split_path(theme_path)
    set_message("Created .ReaperTheme (" .. (name or "theme") .. ") with grid alpha 1.0 and loaded it", "info")
  elseif changed then
    set_message("Grid alpha set to 1.0 in the active theme (backup: .tkbak)", "info")
  else
    set_message("Grid alpha was already at 1.0", "info")
  end
end

local function restore_grid_backup(app)
  if not r.OpenColorThemeFile or not r.GetLastColorThemeFile then
    set_message("OpenColorThemeFile is not available in this REAPER version", "warning")
    return
  end
  local theme_path = r.GetLastColorThemeFile()
  if not theme_path or theme_path == "" or not theme_path:lower():match("%.reapertheme$") then
    set_message("No active .ReaperTheme to restore", "warning")
    return
  end

  local source_path = theme_path .. ".tksrc"
  local source_zip = read_all_text(source_path)
  if source_zip then
    source_zip = source_zip:gsub("[\r\n]+$", "")
    if source_zip ~= "" and file_exists(source_zip) then
      r.OpenColorThemeFile(source_zip)
      refresh_theme_ui()
      set_message("Restored the original theme (.ReaperThemeZip)", "info")
      return
    end
  end

  local backup_path = theme_path .. ".tkbak"
  local text = read_all_text(backup_path)
  if not text then
    set_message("No backup found for the active theme", "warning")
    return
  end
  local file = io.open(theme_path, "wb")
  if not file then
    set_message("Could not write the theme file", "warning")
    return
  end
  file:write(text)
  file:close()
  r.OpenColorThemeFile(theme_path)
  refresh_theme_ui()
  set_message("Restored theme from backup (.tkbak)", "info")
end

local MAX_FAVORITE_THEMES = 10

local function theme_display_name(path)
  local _, name = split_path(path)
  if name then return name end
  return tostring(path or ""):match("([^/\\]+)$") or tostring(path or "")
end

local function favorite_exists(settings, path)
  local lower = tostring(path or ""):lower()
  for _, fav in ipairs(settings.favorite_themes) do
    if tostring(fav.path or ""):lower() == lower then return true end
  end
  return false
end

local function add_favorite_theme(app, settings, path)
  if not path or path == "" then return end
  if not file_exists(path) then
    set_message("Theme file not found", "warning")
    return
  end
  if not path:lower():match("%.reaperthemezip$") and not path:lower():match("%.reapertheme$") then
    set_message("Select a .ReaperTheme or .ReaperThemeZip file", "warning")
    return
  end
  if favorite_exists(settings, path) then
    set_message("Theme is already in favorites", "info")
    return
  end
  if #settings.favorite_themes >= MAX_FAVORITE_THEMES then
    set_message("Favorite themes list is full (max " .. MAX_FAVORITE_THEMES .. ")", "warning")
    return
  end
  settings.favorite_themes[#settings.favorite_themes + 1] = { path = path, name = theme_display_name(path) }
  settings.favorite_selected = #settings.favorite_themes
  persist(app)
  set_message("Theme added to favorites", "info")
end

local function browse_for_theme(app, settings)
  if not r.GetUserFileNameForRead then
    set_message("File browser is not available in this REAPER version", "warning")
    return
  end
  local ok, path = r.GetUserFileNameForRead("", "Select a theme file", "")
  if ok and path and path ~= "" then
    add_favorite_theme(app, settings, path)
  end
end

local function load_favorite_theme(app, settings)
  local fav = settings.favorite_themes[settings.favorite_selected]
  if not fav then
    set_message("No favorite theme selected", "warning")
    return
  end
  if not r.OpenColorThemeFile then
    set_message("OpenColorThemeFile is not available in this REAPER version", "warning")
    return
  end
  if not file_exists(fav.path) then
    set_message("Theme file no longer exists", "warning")
    return
  end
  r.OpenColorThemeFile(fav.path)
  refresh_theme_ui()
  set_message("Loaded theme: " .. (fav.name or "theme"), "info")
end

local function remove_favorite_theme(app, settings)
  local index = settings.favorite_selected
  if not settings.favorite_themes[index] then
    set_message("No favorite theme selected", "warning")
    return
  end
  table.remove(settings.favorite_themes, index)
  settings.favorite_selected = math.max(0, math.min(index, #settings.favorite_themes))
  if #settings.favorite_themes > 0 and settings.favorite_selected == 0 then settings.favorite_selected = 1 end
  persist(app)
  set_message("Theme removed from favorites", "info")
end

local function selected_preset(settings)
  return settings.presets[settings.selected]
end

local function apply_selected(app, settings)
  local preset = selected_preset(settings)
  if not run_action("TK Arrange Background Presets - Apply", function() return apply_preset(preset) end) then
    set_message("Preset could not be applied", "warning")
    return
  end
  persist(app)
  set_message((preset.name or "Preset") .. " applied", "info")
end

local function toggle_a_b(app, settings)
  local a = settings.toggle_a
  local b = settings.toggle_b
  if not settings.presets[a] or not settings.presets[b] then
    set_message("Toggle presets are not valid", "warning")
    return
  end
  local target = (settings.last_toggle == a) and b or a
  if not run_action("TK Arrange Background Presets - Toggle", function() return apply_preset(settings.presets[target]) end) then
    set_message("Toggle apply failed", "warning")
    return
  end
  settings.last_toggle = target
  settings.selected = target
  persist(app)
  set_message("Preset " .. target .. " active via toggle", "info")
end

local function add_preset(app, settings)
  local index = #settings.presets + 1
  settings.presets[index] = { name = "Preset " .. index, apply_tracks = true, apply_grid = true, colors = current_colors() }
  settings.selected = index
  persist(app)
  set_message("New preset added", "info")
end

local function delete_selected(app, settings)
  if #settings.presets <= 1 then
    set_message("At least one preset must remain", "warning")
    return
  end
  table.remove(settings.presets, settings.selected)
  local count = #settings.presets
  settings.selected = math.max(1, math.min(settings.selected, count))
  settings.toggle_a = math.max(1, math.min(settings.toggle_a, count))
  settings.toggle_b = math.max(1, math.min(settings.toggle_b, count))
  settings.last_toggle = math.max(1, math.min(settings.last_toggle, count))
  persist(app)
  set_message("Preset deleted", "info")
end

local function generate_preset_script(app, settings)
  local preset = selected_preset(settings)
  if not preset then return end
  local base_path = app.script_path or ""
  local name = preset.name and preset.name ~= "" and preset.name or ("Preset " .. settings.selected)
  local safe_name = name:gsub("[^%w%s%-_]", ""):gsub("%s+", "_")
  if safe_name == "" then safe_name = "Preset_" .. settings.selected end
  local safe_label = name:gsub("'", "")
  local filename = base_path .. "TK_ABP_Apply_" .. safe_name .. ".lua"
  local L = {}
  L[#L + 1] = "-- @description TK Apply Arrange BG preset: " .. name
  L[#L + 1] = "-- @author TouristKiller"
  L[#L + 1] = "-- @version 1.0"
  L[#L + 1] = ""
  L[#L + 1] = "local r = reaper"
  L[#L + 1] = ""
  L[#L + 1] = "local function hex_to_native(hex)"
  L[#L + 1] = "  local clean = (hex or ''):gsub('%s+', ''):upper()"
  L[#L + 1] = "  if clean:sub(1,1) == '#' then clean = clean:sub(2) end"
  L[#L + 1] = "  return r.ColorToNative(tonumber(clean:sub(1,2),16), tonumber(clean:sub(3,4),16), tonumber(clean:sub(5,6),16))"
  L[#L + 1] = "end"
  L[#L + 1] = ""
  L[#L + 1] = "local _, _, _sec, _cmd = r.get_action_context()"
  L[#L + 1] = "local _prev_cmd = tonumber(r.GetExtState('TK_ABP', 'active_cmd')) or 0"
  L[#L + 1] = "local _prev_sec = tonumber(r.GetExtState('TK_ABP', 'active_sec')) or 0"
  L[#L + 1] = "if _prev_cmd ~= 0 and _prev_cmd ~= _cmd then"
  L[#L + 1] = "  r.SetToggleCommandState(_prev_sec, _prev_cmd, 0)"
  L[#L + 1] = "  r.RefreshToolbar2(_prev_sec, _prev_cmd)"
  L[#L + 1] = "end"
  L[#L + 1] = ""
  L[#L + 1] = "r.Undo_BeginBlock()"
  L[#L + 1] = "r.PreventUIRefresh(1)"
  L[#L + 1] = "r.SetThemeColor('col_arrangebg', hex_to_native('" .. (preset.colors.col_arrangebg or "#000000") .. "'), 0)"
  if preset.apply_tracks then
    for i = 2, #BACKGROUND_FIELDS do
      local key = BACKGROUND_FIELDS[i].key
      L[#L + 1] = "r.SetThemeColor('" .. key .. "', hex_to_native('" .. (preset.colors[key] or "#000000") .. "'), 0)"
    end
  end
  if preset.apply_grid then
    for _, field in ipairs(GRID_FIELDS) do
      L[#L + 1] = "r.SetThemeColor('" .. field.key .. "', hex_to_native('" .. (preset.colors[field.key] or "#000000") .. "'), 0)"
    end
  end
  L[#L + 1] = "r.TrackList_AdjustWindows(false)"
  L[#L + 1] = "r.UpdateTimeline()"
  L[#L + 1] = "r.UpdateArrange()"
  if preset.apply_tracks then
    for _, field in ipairs(DIVIDER_FIELDS) do
      L[#L + 1] = "r.SetThemeColor('" .. field.key .. "', hex_to_native('" .. (preset.colors[field.key] or "#000000") .. "'), 0)"
    end
    L[#L + 1] = "r.ThemeLayout_RefreshAll()"
    L[#L + 1] = "r.TrackList_AdjustWindows(false)"
    L[#L + 1] = "r.UpdateTimeline()"
    L[#L + 1] = "r.UpdateArrange()"
  end
  L[#L + 1] = "r.PreventUIRefresh(-1)"
  L[#L + 1] = "r.Undo_EndBlock('Apply Arrange BG preset: " .. safe_label .. "', -1)"
  L[#L + 1] = "r.SetToggleCommandState(_sec, _cmd, 1)"
  L[#L + 1] = "r.RefreshToolbar2(_sec, _cmd)"
  L[#L + 1] = "r.SetExtState('TK_ABP', 'active_cmd', tostring(_cmd), true)"
  L[#L + 1] = "r.SetExtState('TK_ABP', 'active_sec', tostring(_sec), true)"
  local file = io.open(filename, "w")
  if not file then
    set_message("Could not write script file", "warning")
    return
  end
  file:write(table.concat(L, "\n") .. "\n")
  file:close()
  if r.AddRemoveReaScript then r.AddRemoveReaScript(true, 0, filename, true) end
  set_message("Script added to action list: TK_ABP_Apply_" .. safe_name .. ".lua", "info")
end

local function preset_label(settings, index)
  local preset = settings.presets[index]
  local name = preset and preset.name and preset.name ~= "" and preset.name or ("Preset " .. index)
  if index == settings.toggle_a then name = name .. " [A]" end
  if index == settings.toggle_b then name = name .. " [B]" end
  return name
end

local function draw_color_row(ctx, app, settings, field)
  local preset = selected_preset(settings)
  local value = preset.colors[field.key] or "#000000"
  local flags = r.ImGui_ColorEditFlags_NoInputs() | r.ImGui_ColorEditFlags_NoLabel()
  r.ImGui_PushID(ctx, field.key)
  local changed, picked = r.ImGui_ColorEdit4(ctx, "##swatch", hex_to_imgui_color(value), flags)
  if changed then
    preset.colors[field.key] = imgui_color_to_hex(picked)
    persist(app)
  end
  r.ImGui_SameLine(ctx, 0, UIScale.gap(8))
  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.text, field.label)
  r.ImGui_PopID(ctx)
end

local function draw_color_section(ctx, app, settings, title, fields)
  if r.ImGui_CollapsingHeader(ctx, title) then
    for _, field in ipairs(fields) do draw_color_row(ctx, app, settings, field) end
  end
end

function M.init(app)
  ensure_settings(app)
end

function M.draw(app)
  local ctx = app.ctx
  local settings = ensure_settings(app)
  local button_h = UIScale.button_h(ctx)
  local gap = UIScale.gap(6)

  r.ImGui_TextColored(ctx, Theme.colors.accent, "Arrange Background Presets")
  r.ImGui_Separator(ctx)

  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Preset")
  r.ImGui_SameLine(ctx, 0, gap)
  r.ImGui_PushItemWidth(ctx, -1)
  if r.ImGui_BeginCombo(ctx, "##arrange_bg_preset", preset_label(settings, settings.selected)) then
    for index = 1, #settings.presets do
      local is_selected = settings.selected == index
      if r.ImGui_Selectable(ctx, index .. ". " .. preset_label(settings, index), is_selected) then
        settings.selected = index
        persist(app)
      end
      if is_selected then r.ImGui_SetItemDefaultFocus(ctx) end
    end
    r.ImGui_EndCombo(ctx)
  end
  r.ImGui_PopItemWidth(ctx)

  local half = math.max(UIScale.round(60), math.floor(((r.ImGui_GetContentRegionAvail(ctx) or UIScale.round(200)) - gap) / 2))
  if r.ImGui_Button(ctx, "New##arrange_bg_new", half, button_h) then add_preset(app, settings) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Add a preset from current theme colors") end
  r.ImGui_SameLine(ctx, 0, gap)
  if r.ImGui_Button(ctx, "Delete##arrange_bg_delete", half, button_h) then delete_selected(app, settings) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Delete the selected preset") end

  r.ImGui_Spacing(ctx)
  local preset = selected_preset(settings)
  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Name")
  r.ImGui_SameLine(ctx, 0, gap)
  r.ImGui_PushItemWidth(ctx, -1)
  local name_changed, new_name = r.ImGui_InputText(ctx, "##arrange_bg_name", preset.name or "")
  if name_changed then
    preset.name = new_name
    persist(app)
  end
  r.ImGui_PopItemWidth(ctx)

  local tracks_changed, apply_tracks = r.ImGui_Checkbox(ctx, "Track backgrounds", preset.apply_tracks ~= false)
  if tracks_changed then
    preset.apply_tracks = apply_tracks
    persist(app)
  end
  local grid_changed, apply_grid = r.ImGui_Checkbox(ctx, "Grid colors", preset.apply_grid ~= false)
  if grid_changed then
    preset.apply_grid = apply_grid
    persist(app)
  end

  r.ImGui_Spacing(ctx)
  local _, remaining_h = r.ImGui_GetContentRegionAvail(ctx)
  local info_h = UI.info_line_height(ctx)
  local footer_h = button_h * 6 + gap * 10 + UIScale.round(8)
  local list_h = math.max(UIScale.round(80), (remaining_h or UIScale.round(300)) - info_h - footer_h)
  if r.ImGui_BeginChild(ctx, "##arrange_bg_colors", 0, list_h, 1) then
    draw_color_section(ctx, app, settings, "Background colors", BACKGROUND_FIELDS)
    draw_color_section(ctx, app, settings, "Grid colors", GRID_FIELDS)
    draw_color_section(ctx, app, settings, "Track divider lines", DIVIDER_FIELDS)
  end
  r.ImGui_EndChild(ctx)

  r.ImGui_Spacing(ctx)
  local half_apply = math.max(UIScale.round(60), math.floor(((r.ImGui_GetContentRegionAvail(ctx) or UIScale.round(200)) - gap) / 2))
  if r.ImGui_Button(ctx, "Apply##arrange_bg_apply", half_apply, button_h) then apply_selected(app, settings) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Apply the selected preset to the theme") end
  r.ImGui_SameLine(ctx, 0, gap)
  if r.ImGui_Button(ctx, "Reset colors##arrange_bg_reset", half_apply, button_h) then
    if run_action("TK Arrange Background Presets - Reset", reset_theme_colors) then
      set_message("Theme colors reset to defaults", "info")
    else
      set_message("Reset failed", "warning")
    end
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Reset the live colors managed by this module back to the theme defaults (in-memory only, not written to the theme file)") end

  local third = math.max(UIScale.round(48), math.floor(((r.ImGui_GetContentRegionAvail(ctx) or UIScale.round(200)) - gap * 2) / 3))
  if r.ImGui_Button(ctx, "Set A##arrange_bg_set_a", third, button_h) then
    settings.toggle_a = settings.selected
    persist(app)
    set_message("Preset " .. settings.selected .. " set as toggle A", "info")
  end
  r.ImGui_SameLine(ctx, 0, gap)
  if r.ImGui_Button(ctx, "Set B##arrange_bg_set_b", third, button_h) then
    settings.toggle_b = settings.selected
    persist(app)
    set_message("Preset " .. settings.selected .. " set as toggle B", "info")
  end
  r.ImGui_SameLine(ctx, 0, gap)
  if r.ImGui_Button(ctx, "Toggle##arrange_bg_toggle", third, button_h) then toggle_a_b(app, settings) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Switch between toggle presets A and B") end

  if r.ImGui_Button(ctx, "Generate script##arrange_bg_generate", -1, button_h) then generate_preset_script(app, settings) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Write a standalone apply/toggle action script for this preset and add it to the action list") end

  local half3 = math.max(UIScale.round(60), math.floor(((r.ImGui_GetContentRegionAvail(ctx) or UIScale.round(200)) - gap) / 2))
  if r.ImGui_Button(ctx, "Grid full alpha##arrange_bg_gridfull", half3, button_h) then grid_full_alpha(app) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Write grid line alpha 1.0 into the active theme file (.ReaperTheme) and reload it, so the grid color sliders cover the full range. Makes a one-time backup first (.tkbak, or .tksrc for zip themes)") end
  r.ImGui_SameLine(ctx, 0, gap)
  if r.ImGui_Button(ctx, "Restore theme file##arrange_bg_restore", half3, button_h) then restore_grid_backup(app) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Undo Grid full alpha: restore the theme file from its backup and reload it. Only works after Grid full alpha has made a backup (.tkbak / .tksrc)") end

  r.ImGui_Separator(ctx)
  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Themes")
  r.ImGui_SameLine(ctx, 0, gap)
  r.ImGui_PushItemWidth(ctx, -1)
  local fav_count = #settings.favorite_themes
  local fav_current = settings.favorite_themes[settings.favorite_selected]
  local fav_preview = (fav_current and fav_current.name) or "No favorite themes"
  if r.ImGui_BeginCombo(ctx, "##arrange_bg_fav_theme", fav_preview) then
    for index = 1, fav_count do
      local fav = settings.favorite_themes[index]
      local is_selected = settings.favorite_selected == index
      if r.ImGui_Selectable(ctx, index .. ". " .. (fav.name or "theme"), is_selected) then
        settings.favorite_selected = index
        persist(app)
      end
      if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, fav.path or "") end
      if is_selected then r.ImGui_SetItemDefaultFocus(ctx) end
    end
    r.ImGui_EndCombo(ctx)
  end
  r.ImGui_PopItemWidth(ctx)

  local third2 = math.max(UIScale.round(48), math.floor(((r.ImGui_GetContentRegionAvail(ctx) or UIScale.round(200)) - gap * 2) / 3))
  if r.ImGui_Button(ctx, "Load##arrange_bg_fav_load", third2, button_h) then load_favorite_theme(app, settings) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Load the selected favorite theme") end
  r.ImGui_SameLine(ctx, 0, gap)
  if r.ImGui_Button(ctx, "Add...##arrange_bg_fav_add", third2, button_h) then browse_for_theme(app, settings) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Browse for a .ReaperTheme(Zip) file to add to favorites (max " .. MAX_FAVORITE_THEMES .. ")") end
  r.ImGui_SameLine(ctx, 0, gap)
  if r.ImGui_Button(ctx, "Remove##arrange_bg_fav_remove", third2, button_h) then remove_favorite_theme(app, settings) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Remove the selected theme from favorites") end

  local info_text = state.message or ((preset.name or "Preset") .. " selected")
  UI.draw_info_line(ctx, info_text, { severity = state.message_severity })
end

return M
