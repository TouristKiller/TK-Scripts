-- Module icons as images: icons/modules/<style>/<size>/<id>.png, white on
-- transparent, tinted with the colour they are drawn in. Made by
-- tools/make_module_icons.py. Styles: "line" and "bold" (setting
-- module_icon_style). A module without an image returns false, so the caller
-- draws its own icon instead.

local r = reaper
local M = {}

local SIZES = { 24, 48, 96 }
local cache = {}      -- [ctx][path] = image or false (no file)
local cache_ctx = nil

local function image_for(ctx, base, style, id, px)
  if cache_ctx ~= ctx then
    cache, cache_ctx = {}, ctx
  end
  local want = SIZES[#SIZES]
  for _, s in ipairs(SIZES) do
    if s >= px then want = s break end
  end
  local path = base .. "icons/modules/" .. style .. "/" .. want .. "/" .. id .. ".png"
  local img = cache[path]
  if img == nil then
    img = false
    if r.file_exists(path) then
      local ok, made = pcall(r.ImGui_CreateImage, path)
      if ok and made then
        if r.ImGui_Attach then pcall(r.ImGui_Attach, ctx, made) end
        img = made
      end
    end
    cache[path] = img
  end
  if img and r.ImGui_ValidatePtr and not r.ImGui_ValidatePtr(img, "ImGui_Image*") then
    cache[path] = nil
    return nil
  end
  return img or nil
end

function M.style(settings)
  local s = settings and settings.module_icon_style
  return (s == "bold") and "bold" or "line"
end

-- true when an image was drawn
function M.draw(app, draw_list, id, cx, cy, size, color)
  if not (app and id and id ~= "" and r.ImGui_DrawList_AddImage) then return false end
  local img = image_for(app.ctx, app.script_path, M.style(app.settings), id, size)
  if not img then return false end
  local h = size * 0.5
  r.ImGui_DrawList_AddImage(draw_list, img, cx - h, cy - h, cx + h, cy + h, 0, 0, 1, 1, color)
  return true
end

return M
