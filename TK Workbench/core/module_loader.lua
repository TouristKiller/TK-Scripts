local M = {}

local function record_error(app, key, err)
  if app.record_module_error then app.record_module_error(key, err) else app.module_errors[key] = tostring(err) end
end

function M.load(app, module_names)
  app.modules = {}
  app.modules_by_id = {}
  app.module_errors = app.module_errors or {}

  for _, name in ipairs(module_names) do
    local ok, module = pcall(require, "modules." .. name)
    if ok and type(module) == "table" then
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