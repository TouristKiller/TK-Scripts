local r = reaper
local Theme = require("core.theme")
local UIScale = require("core.ui_scale")
local Navigator = require("core.navigator")

-- The same map Transport carries as a card, on its own so it can be put
-- anywhere - a pane of the split view being the point of it. Both draw the code
-- in core/navigator; the only thing that differs is how much room they give it.
local M = {
  id = "navigator",
  title = "Navigator",
  icon = "NAV",
  version = "0.1.0"
}

function M.draw(app)
  local ctx = app.ctx
  local width, height = r.ImGui_GetContentRegionAvail(ctx)
  width = math.max(UIScale.round(80), width or UIScale.round(240))
  height = math.max(UIScale.round(60), height or UIScale.round(160))
  if not Navigator.available() then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Navigator needs GetSet_ArrangeView2 (REAPER) or SWS.")
    return
  end
  -- Fills the pane rather than a fixed strip: a taller pane gives every track
  -- its own row instead of squeezing them all into 120 pixels.
  Navigator.draw(ctx, app, width, height, "Navigator")
end

return M
