-- @description TK Idea Swap preview for tracks
-- @author TouristKiller
-- @version 0.1.0
-- @changelog:
--   + Initial release: replaces the selected Idea Vault preview items (put in
--     by Insert audio) with the idea's real tracks, lined up so the part plays
--     where the audio did. Works without TK Workbench running, so it can sit
--     in the media item context menu.

local r = reaper

local SCRIPT_NAME = "TK Idea Swap preview for tracks"

local script_path = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
local sep = package.config:sub(1, 1)
package.path = script_path .. "?.lua;" .. script_path .. "?" .. sep .. "init.lua;" .. package.path

local ok_store, Store = pcall(require, "core.idea_vault_store")
if not ok_store then
  r.ShowMessageBox("Could not load the Idea Vault store:\n\n" .. tostring(Store), SCRIPT_NAME, 0)
  return
end

local entries = Store.preview_items()
if #entries == 0 then
  r.ShowMessageBox("None of the selected items is an Idea Vault preview.\n\n"
    .. "Previews put in the project with Insert audio (or by dragging an idea\n"
    .. "onto a track) can be swapped for the tracks they came from.", SCRIPT_NAME, 0)
  return
end

local _, failed = Store.swap_for_tracks(entries)
if #failed > 0 then
  r.ShowMessageBox(Store.swap_failure_text(failed), SCRIPT_NAME, 0)
end
