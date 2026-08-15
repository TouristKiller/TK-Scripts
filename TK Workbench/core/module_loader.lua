local r = reaper

local M = {}

local function record_error(app, key, err)
  if app.record_module_error then app.record_module_error(key, err) else app.module_errors[key] = tostring(err) end
end

-- A module listed here but not present on disk is a module that was not
-- installed, not a module that is broken: an older package, a partial ReaPack
-- update, or a name that shipped ahead of its file. Users got a wall of
-- "no file ..." lines in the error log for something they cannot act on, so
-- these are skipped quietly. A file that IS there and fails to load - a syntax
-- error, a missing core dependency - still reports as loudly as before.
local function module_installed(app, name)
  local path = tostring(app.script_path or "") .. "modules" .. package.config:sub(1, 1) .. name .. ".lua"
  if r and r.file_exists then return r.file_exists(path) end
  local file = io.open(path, "r")
  if file then file:close(); return true end
  return false
end

function M.load(app, module_names)
  app.modules = {}
  app.modules_by_id = {}
  app.module_errors = app.module_errors or {}
  app.missing_modules = {}

  for _, name in ipairs(module_names) do
    local ok, module = pcall(require, "modules." .. name)
    if not ok and not module_installed(app, name) then
      app.missing_modules[#app.missing_modules + 1] = name
    elseif ok and type(module) == "table" then
      module.id = module.id or name
      module.title = module.title or module.id
      if module.init then
        local init_ok, init_err = pcall(module.init, app)
        if not init_ok then record_error(app, module.id .. ".init", init_err) end
      end
      app.modules[#app.modules + 1] = module
      app.modules_by_id[module.id] = module
    else
      record_error(app, name .. ".load", module)
    end
  end
end

return M