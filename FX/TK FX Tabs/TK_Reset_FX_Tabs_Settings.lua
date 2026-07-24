local r = reaper

local section = "TK_FX_TABS"
local keys = {
  "select_track_on_open",
  "auto_open_on_start",
  "capture_external_floating",
  "center_fx_in_reaper_window",
  "follow_fx_position",
  "show_track_numbers",
  "content_mode",
  "tab_filter_mode",
  "plugin_overlap_y",
  "vertical_flip",
  "vertical_offset",
  "topbar_left_overhang",
  "topbar_right_overhang",
  "fixed_fx_size",
  "fixed_fx_width",
  "fixed_fx_height",
  "theme_preset",
  "theme_topbar_border",
  "auto_hide_when_empty",
  "detached_mode",
  "custom_themes",
  "custom_theme_name"
}

for i = 1, #keys do
  r.DeleteExtState(section, keys[i], true)
end

r.ShowMessageBox("TK FX Tabs instellingen zijn gereset.\nStart TK FX Tabs opnieuw.", "TK FX Tabs", 0)
