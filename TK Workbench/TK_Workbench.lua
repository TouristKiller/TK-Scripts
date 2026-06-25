-- @description TK Workbench
-- @author TouristKiller
-- @version 0.5.1
-- @changelog:
-- v0.5.1
--   + Instrument Rack: Pinned parameters with discrete steps (e.g. modes) can now be shown as a click-to-cycle button that steps through each value, with drag to scrub and double-click to reset
--   + Instrument Rack: Stepped values are detected even when a plugin does not report step sizes, by briefly scanning the parameter's value labels
--   + Instrument Rack: Button-style pinned parameters automatically pick a stepped value cycle or an on/off button, and the cycle only appears when Button layout is selected
--   + Instrument Rack: Removed the border around pinned parameter buttons and made them slightly wider for easier reading
--   + Instrument Rack: Long values inside pinned parameter buttons are now truncated to fit the button width
--   + Instrument Rack: Added a per-parameter right-click option to show the name or value, and to show or hide the label under the knob/button, with a matching global default
--   + Instrument Rack: Added options to center the track name with an optional badge background, and to center the plugin name in FX tiles
--   + Instrument Rack: Horizontal FX tiles now widen automatically for 6-column parameter layouts so parameter spacing stays even
--   + Instrument Rack: Settings window now uses a two-column layout in horizontal orientation for a more compact view
--   + Instrument Rack: Removed the "Show value overlay while dragging" option
--   + Instrument Rack: Fixed per-parameter name/value and label-under choices not being saved with the project
--   + Instrument Rack: Add FX and Quick Add buttons now stay clearly visible in every theme, even when not hovered
--   + Instrument Rack: Quick Add now shows AU and AU instrument plugins under All Plugins
--   + Instrument Rack: Quick Add folders are now sorted naturally so numbered folders appear in order (1, 2, 3, ... 15) instead of scrambled
--   + Instrument Rack: Added a track color saturation slider to tone down inherited track colors
--   + Instrument Rack: Settings window now uses a two-column layout in vertical orientation as well, for a more compact view
--   + Instrument Rack: Fixed the horizontal (tilt) scroll wheel not scrolling the horizontal rack
-- v0.5.0
--   + FX Groups: Added a new module to link FX parameters across multiple tracks with a live, per-FX sync engine
--   + FX Groups: Manage groups in a compact, collapsible list with inline rename (double-click), color swatch, active toggle, and track management
--   + FX Groups: Link or unlink individual FX and parameters, with a per-FX SYNC button and selectable source track
--   + FX Groups: Add an FX to every track in a group at once via the cascading Quick Add menu
--   + Instrument Rack: Added response curves to macro parameter mappings with Power, S-Curve, Quantize, and Bipolar curve types
--   + Instrument Rack: Added a draggable graphical curve preview per mapping that reflects the selected curve type and invert state live
--   + Instrument Rack: Drag the curve pad up or down to change the curve amount and double-click to reset it to linear
--   + Instrument Rack: Curve type and amount are stored per mapping and persist with the project, defaulting to a linear Power curve for older projects
--   + Instrument Rack: Added a Highlight instruments option to visually distinguish instrument plugins in the rack
--   + Instrument Rack: Added a Plugin type badge on screenshot option showing a color-coded VST3, VST, CLAP, JS, AU, or LV2 badge per FX tile
--   + Instrument Rack: Added a Wet knob on FX containers (including nested containers) in both the vertical and horizontal rack, with drag to adjust and double/right-click to reset
--   + Instrument Rack: Container add zones now show the same Add FX and Quick Add buttons as the regular add zone, in both the vertical and horizontal rack
--   + Instrument Rack: Matched the container add and Quick Add button sizing to the regular add zone for a consistent look
--   + Home: Added an Instrument Rack (H) tile and module dropdown entry to quickly open the horizontal Instrument Rack
--   + Instrument Rack: Added an optional vertical title bar on the left of the horizontal rack, with the track number in a darker box on top, the truncated track name stacked below, and the pin, settings, and close buttons
--   + Instrument Rack: Tightened the spacing between collapsed section headers in the horizontal rack
-- v0.4.5
--   + Instrument Rack: Added a Quick Add cascading FX menu with Favorites, Recent, All Plugins (grouped by type), Category, Developer, Folders, FXChains and Container
-- v0.4.4
--   + Calculator: Added an option in Delay / Reverb to subtract pre-delay from decay/RT60 values, including selectable pre-delay source
--   + Instrument Rack: Fixed horizontal section collapse headers so text stays inside the header when tiles are compact or screenshots are hidden
--   + Instrument Rack: Simplified horizontal section labels to TRACK, INPUT, and TAKE
-- v0.4.3
--   + Instrument Rack: Added an option to hide parallel/serial signal flow badges in both vertical and horizontal layouts
--   + Instrument Rack: Horizontal header now includes a close dot next to the settings (...) button
--   + Instrument Rack: Refined vertical and horizontal spacing for section gaps, add zones, and flow badge placement
--   + Instrument Rack: Input FX section now supports the same flow badges/tree behavior as track FX
--   + Instrument Rack: Take FX tiles now keep parameter-slot space visible for consistent tile height
--   + Instrument Rack: Added Wet knob size and alpha controls, capped Wet knob size to 1.0, and adjusted Wet knob colors to a more neutral style
-- v0.4.2
--   + Preferences: Reorganized into themed tabs (General, Modules, Theme) so all settings live in one window; clicking the settings dot now opens Preferences directly
--   + Preferences: Added a Modules tab to show or hide individual modules in both the home tiles and the module dropdown, with Show all / Hide all
-- v0.4.1
--   + Home: Fixed module icons drawing outside their shapes at non-100% UI scaling (e.g. Calculator buttons and Arrange BG grid no longer overflow)
-- v0.4.0
--   + Calculator: Added a new module with Delay, Gain, Note, and Samples tabs for studio calculations
--   + Calculator: Delay tab shows note times (straight/dotted/triplet) with click-to-copy and ms/Hz toggle, plus reverb pre-delay and decay references
--   + Calculator: Gain tab converts dB to linear/percent/power and back, with a pan law reference
--   + Calculator: Note tab converts notes to frequency/MIDI and frequency to the nearest note with cents detune, using a configurable A4 reference
--   + Calculator: Samples tab converts milliseconds to samples and back, with note lengths in samples, following project tempo and sample rate (manual override available)
--   + Workbench: Added a mappable module action for opening Calculator
-- v0.3.9
--   + Media Browser: Spacebar now plays/stops the preview and Enter/Return toggles play/pause (resumes from the pause position), matching REAPER's transport; both are ignored while typing in a field
-- v0.3.8
--   + Instrument Rack: Container drop zones now double as add buttons — click one to add an FX straight into that container via the linked TK FX Browser, TK FX Browser Mini, or the internal Plugin Browser, while drag-and-drop into the container keeps working
--   + Instrument Rack: Right-click a container drop zone for Add FX... and Add empty container inside actions
--   + Instrument Rack: Container drop zones now match the look of the regular add button in both the vertical and horizontal rack
--   + Instrument Rack: Fixed a crash in the horizontal rack when a container scrolled off-screen
--   + Instrument Rack: Added modifier-click shortcuts on the whole FX tile (vertical and horizontal rack) — Alt-click deletes the plugin without confirmation, Shift-click bypasses, and Ctrl+Shift-click toggles offline
--   + Instrument Rack: TK FX Browser, TK FX Browser Mini, and the Plugin Browser now route added FX to the Input or Take chain when adding from the rack's Input or Item FX sections
--   + Instrument Rack: Opening an already running external TK FX Browser or Mini now shows it instead of toggling its visibility off
--   + Instrument Rack: Input and Item FX sections now always show their add button so you can add or drop the first FX even when the chain is empty (vertical and horizontal rack)
--   + Instrument Rack: Pinned parameter knobs and the wet knob now keep their last known values when an FX is set offline instead of disappearing or resetting to 100%
--   + Instrument Rack: Pinned parameter knobs now dim uniformly when an FX is set offline or bypassed
--   + Instrument Rack: Each FX section (Track, Input, Take) in the vertical rack now has a collapsible header with a chevron, sharing the collapse state with the horizontal rack
--   + Instrument Rack: Removed the redundant track name shown beneath the Input and Item FX section headers in the vertical rack
--   + Instrument Rack: Replaced the wet button with a rotary wet knob on the left of each FX tile that is draggable straight away, shows the live percentage while dragging, and resets to 100% on double/right-click
--   + Instrument Rack: Collapsing an FX tile now keeps the wet knob, name, and controls visible and only hides the screenshot and pinned parameters
--   + Instrument Rack: Renamed the take FX source toggle to Show take FX (selected item) with a clearer tooltip
--   + Instrument Rack: Double-click a pinned parameter under the screenshot to reset it to its default value (also in the horizontal rack)
--   + Instrument Rack: Saving plugin default pins now also stores the current parameter values, with a Restore saved parameter values on apply option to recall them automatically
--   + Instrument Rack: Grouped the settings popup into labelled sections (Display, Controls, FX sources, Layout, Default parameter pins, Add FX target) with divider lines
--   + Instrument Rack: Section header colors now match the horizontal banner opacity instead of appearing brighter
--   + Instrument Rack: Horizontal rack now also scrolls with a physical horizontal scroll wheel or tilt wheel
-- v0.3.7
--   + Media Browser: Fixed the Add Location folder picker being restricted to Desktop/Users on some systems
--   + Media Browser: Hold Shift while dragging a file onto a track to drop it into a new fixed lane (auto-enables fixed lanes)
--   + Media Browser: Added Stop preview on insert/load option (right-click the sync button); preview stops automatically after inserting to arrange or loading into RS5K/Cartridge
-- v0.3.6
--   + Notes: Added a scrollbar on the right of the body editor when text/images exceed the visible area
--   + Notes: Added mouse wheel scrolling inside the body editor
--   + Notes: Typing/pasting is no longer limited to the window height; the editor scrolls instead
-- v0.3.5
--   + Instrument Rack: Horizontal rack now scrolls horizontally using the dominant mouse wheel axis
--   + Instrument Rack: Added an option to invert the horizontal wheel scroll direction
--   + Instrument Rack: Added a Signal flow order option to arrange sections as Input > Take > Track
--   + Instrument Rack: Horizontal rack now follows Workbench theme and UI scale changes live without a restart
--   + Instrument Rack: Added an option to color section headers by track color
--   + Instrument Rack: Added an item name overlay on item FX tiles with item color background and the item name in the info bar and tooltip
--   + Instrument Rack: Raised the screenshot height range up to 400 px
--   + Instrument Rack: Added per-plugin default parameter pins with save, apply, and clear actions plus an optional auto-apply on load
--   + Instrument Rack: Added a settings (...) button on FX tiles that opens the same menu as right-click
--   + Workbench: Added a Background opacity slider for the main floating window
--   + Workbench: Added a separate Module panel opacity slider for module backgrounds
--   + Workbench: Preferences window now auto-resizes to its content and keeps the close button aligned to the right edge
--   + Media Browser: Sync rate to project tempo now reads embedded file BPM (ACID, ID3, Vorbis, XMP) before falling back to length matching
--   + Arrange BG: Added a new module for managing arrange, track, grid, and divider theme colors as presets
--   + Arrange BG: Added preset apply, A/B toggle, per-preset track/grid scope, color picker, and standalone action script generation
--   + Arrange BG: Added Reset colors for live theme colors and Restore theme file from backup
--   + Arrange BG: Added Grid full alpha to unlock the full grid color range with a one-time theme file backup
--   + Arrange BG: Added favorite theme loader supporting .ReaperTheme and .ReaperThemeZip files
--   + Workbench: Added mappable module actions for opening Arrange BG, Timepiece, and Track Tags
-- v0.3.4
--   + Workbench: Added a side-by-side option for split view alongside the stacked layout
-- v0.3.3
--   + Instrument Rack: Added a horizontal Instrument Rack window that can be opened from the rack settings
--   + Instrument Rack: Added a selectable macro count of 8 or 16
--   + Instrument Rack: Tiles now collapse horizontally into a narrow strip in horizontal layout
-- v0.3.2
--   + Workbench: Added a clear (X) button to module search fields in Media Browser, Plugin Browser, Project Browser, Script Launcher, Track Tags, and Action Browser
--   + Media Browser: Raised the default file scan cap to 200000 and added a configurable Max files setting up to five million
-- v0.3.1
--   + Control Room: Restored master meter screen state across REAPER restarts
--   + Control Room: Added a focused meter view with Back, Reset, settings, removable info labels, and adaptive meter height
--   + Notes: Kept the custom body editor typing target active so REAPER global shortcuts do not intercept note input
-- v0.3.0
--   + Workbench: Added manual UI scaling presets for small touch screens through large high-resolution displays
--   + Workbench: Added automatic contrast correction for readable text on light and dark theme backgrounds
--   + Workbench modules: Scaled module controls, panels, lists, grids, cards, meters, previews, and editor layouts across the Workbench
--   + Workbench: Fixed the module selector preview label after simplifying the title header
-- v0.2.9
--   + Tags: Restored previous TCP/MCP visibility when clearing active tag filters instead of forcing all tracks visible
--   + Tags: Added Restore previous visibility alongside explicit Show all tracks
-- v0.2.8
--   + Workbench: Fixed ReaPack delivery for the Tags module by adding modules/track_tags.lua to the package index
-- v0.2.7
--   + Workbench: Added auto-collapse edge offset and close-delay preferences
--   + Workbench: Kept auto-collapse expanded while popups, dropdowns, or hovered popup windows are active
--   + Workbench: Added module error logging to workbench_errors.txt and improved module error status labels
--   + Workbench: Stopped stale draw errors from inactive modules from taking over the global status bar
--   + Tags: Hardened track GUID handling with persistent fallbacks and skipped tracks without stable GUIDs
--   + Tags: Improved portable install store path handling, color normalization, and compact pane height safety
-- v0.2.6
--   + Workbench: Added floating-window auto-collapse with REAPER edge pinning, a keep-expanded pin button, and a 1px transparent hover strip
--   + Workbench: Added auto-height modes for manual height, arrange height, REAPER window height, and arrange-to-window-bottom height
--   + Workbench: Improved auto-collapse positioning with native-to-ImGui coordinate conversion for scaling and multi-monitor setups
--   + Workbench: Disabled auto-collapse preferences while Workbench is docked to clarify that auto-collapse is floating-only
--   + Plugin Browser: Fixed external FX drag overlay positioning on secondary monitors
--   + Plugin Browser: Kept Workbench expanded during pending and active external FX drags to prevent interrupted drops
-- v0.2.5
--   + Workbench: Added split screen mode with two stacked modules, a resizable splitter, swap control, and shared shell controls
--   + Workbench: Added Timepiece module with a large clock display for time, local clock, measures/beats, beats/ticks, seconds, samples, and frames
--   + Timepiece: Added optional full-width next marker bar below region progress and above the badges
--   + Timepiece: Added optional project position, region progress, play rate, context info, local time, and local date badges
--   + Timepiece: Added settings popup controls for status, BPM, signature, display mode, clock position, clock text visibility, and extra badges
--   + Timepiece: Added automatic play position/edit cursor behavior and optional top-aligned clock layout
--   + Timepiece: Added alarm and timer controls with bottom status bars and red clock feedback while ringing
--   + Timepiece: Improved large clock sizing, horizontal alignment, next marker persistence, and compact top layout spacing
--   + Workbench modules: Unified Plugin Browser, Instrument Rack, FX Chain Builder, and Timepiece settings access with right-aligned ... buttons
--   + Tags: Added global track tag module compatible with TK FX Browser tag storage
--   + Tags: Added search, tag creation, color editing, rename, global remove, and per-track/selected-track tag removal
--   + Tags: Added single and Ctrl multi-tag selection with TCP/MCP visibility filtering and matching REAPER track selection
--   + Tags: Added full track list navigation with active tag match highlighting even when TCP tracks are hidden
--   + Tags: Added context actions for selecting, muting, arming, soloing, solo-selecting, and clearing tags from tagged tracks
-- v0.2.4
--   + Workbench: Improved REAPER Theme color mapping using native main window, docker, list, transport, routing, marker, region, and meter theme colors
--   + Workbench: Added REAPER Theme - Panel and REAPER Theme - Color preset variants
--   + Workbench: Added contrast-aware text, dim text, and badge text selection for REAPER-derived theme presets
-- v0.2.3
--   + Instrument Rack: Added TK FX Browser Mini as an Add FX target
--   + Project Browser: Added compact list view with tighter row spacing
--   + Media Browser: Added compact list view with tighter row spacing
--   + Project Browser: Browsed folders are now added immediately instead of only filling the location field
--   + Action Clipboard: Added Ctrl+V paste from the system clipboard directly into hovered slots
--   + Action Clipboard: Added context menu paste from clipboard for individual slots
--   + Action Clipboard: Added support for pasted numeric command IDs, named commands, and exact action names
--   + Action Clipboard: Added hovered-slot keyboard interception so Ctrl+V works without first focusing Workbench
--   + Action Clipboard: Prevented REAPER's global Paste items/tracks command from being captured during slot paste
--   + Action Browser: Clipboard slot menus now follow the configured Action Clipboard slot count
--   + Project Browser: Added project audio preview discovery and playback for proxy and .tkprev preview files
--   + Project Browser: Added preview creation from full project render, time selection, or a custom audio file
--   + Project Browser: Added preview management popup to play, select active, and delete project previews
--   + Project Browser: Added persistent active preview selection per project
--   + Project Browser: Added preview volume, progress display, and compact playback controls
--   + Project Browser: Added theme-aware preview volume slider styling and a square No image fallback
--   + Project Browser: Custom audio preview file picker now opens in the project's folder
-- v0.2.2
--   + Action Clipboard: Added cross-platform TK Action Capture binaries for Windows, macOS and Linux delivery
--   + Native capture: Updated ReaPack delivery so platform artifacts install into the Workbench folder for manual UserPlugins copy
-- v0.2.1
--   + Action Browser: Added Action Clipboard footer with 5 recent, lockable action slots
--   + Action Browser: Added C shortcut to show or hide the Action Clipboard footer
--   + Action Browser: Added context menu actions to add actions to the clipboard or directly to a specific slot
--   + Action Clipboard: Added mappable run and lock-toggle slot scripts that work without Workbench being open
--   + Action Clipboard: Added persistent slot storage, external refresh handling, clearer lock styling, and shortcut details in tooltips
--   + Media Browser: Auto Categories now works on the currently open subfolder when folder browsing is active
--   + Project Browser: Added optional folder view for browsing subfolders in projects, project templates, and track templates
--   + Plugin Browser: Added virtual instrument new-track action with MIDI input selection
--   + Workbench: Added REAPER Theme preset for deriving Workbench colors from the active REAPER theme
--   + Workbench: Added mappable module actions for opening Home and each Workbench module, with automatic Workbench launch
--   + Workbench: Added separate Action Clipboard Actions and Module Actions folders for cleaner REAPER action organization
--   + Workbench: Added ExtState command handling for external clipboard and module action scripts
-- v0.1.7
--   + Project Browser: Added compact Workbench module for projects, project templates, and track templates
--   + Project Browser: Added per-type user locations, recursive scanning, search/filter, date sorting, cover previews, and open/insert actions
--   + Project Browser: Added read-only project metadata for BPM, signature, tracks, sample rate, modified date, and lightweight length detection
-- v0.1.5
--   + Media Browser: Added optional fade-in/fade-out handling for onboard audio previews
--   + Media Browser: Added configurable preview fade duration, disabled by default
--   + Media Browser: Added configurable audio switch gap and delayed source cleanup for onboard preview file switching
--   + Media Browser: Added optional tape-speed rate mode so pitch follows persistent rate changes while previewing files
--   + Media Browser: Added optional double-click-to-open behavior for folder browsing
--   + Plugin Browser: Added right-click screenshot capture with normal and OpenGL/DX modes, saved to the central TK FX BROWSER Screenshots folder
--   + Plugin Browser: Improved screenshot matching for x86/x86 bridged, Mono/Stereo, sanitized underscore, and manufacturer-prefix variants
--   + Control Room: Added monitor output modes for Stereo, Mono Sum, L/R Source, and L/R Speaker checks
--   + Control Room: Added setup and right-click lane controls for monitor output modes
--   + Control Room: Added Stereo and Mono Sum output modes for cue outputs, including setup and right-click lane controls
--   + Track Recall: Added multi-track save for selected tracks with automatic track-name based recall names
-- v0.1.4
--   + Media Browser: Added lazy per-location cache loading with explicit refresh
--   + Media Browser: Added compact folder browsing with subfolder rows
--   + Media Browser: Added folder cover-art thumbnails for cover/folder/front images
--   + Media Browser: Reworked media cache storage to avoid large Lua cache load errors
--   + Media Browser: Added option for random navigation during auto-preview playback
--   + Media Browser: Fixed drag-and-drop insertion into REAPER fixed item lanes
--   + Media Browser: Added audio-file context menu actions for RS5K and Cartridge loading
--   + Media Browser: Added RS5K Manager pad load/create/delete actions from the audio context menu
--   + Media Browser: Added RS5K Manager toggle action matching the standalone browser workflow
--   + Workbench: Added global tooltip enable and delay preferences
--   + Workbench: Added optional compact Info box footer with clipped text and hover details
--   + Workbench: Centralized Info box positioning so it stays aligned across modules
--   + Workbench: Improved module error display with compact diagnostics
--   + Color Studio: Added optional auto-apply for matching track color rules
-- v0.1.3
--   + Plugin Browser: Added option to return to Rack after adding FX from Rack
--   + Plugin Browser: Added option to return to FX Chain Builder after adding FX to Chain Builder
--   + Media Browser: Stop active preview playback when Workbench is closed by shortcut or action toggle
-- v0.1.2
--   + Added support for secondary Workbench launchers with separate script name and config file
-- v0.1.1
--   + Home: Added drag-and-drop module tile reordering with matching module dropdown order
--   + Instrument Rack: Added MIDI learn and hardware control support for rack macros
--   + Instrument Rack: Added absolute, relative, invert, range calibration, and sensitivity options for macro MIDI control
--   + Instrument Rack: Added global rack macro footer with 8 macro controls
--   + Instrument Rack: Added Assign to Macro workflow from pinned parameter controls
--   + Instrument Rack: Added project-persistent macro assignments with range and invert support
--   + Script Launcher: Added Capture Window for thumbnail screenshot capture
--   + Script Launcher: Added right-click context menu with Edit and Delete
--   + Script Launcher: Stabilized context-menu edit flow


local r = reaper

local SCRIPT_NAME = rawget(_G, "TK_WORKBENCH_SCRIPT_NAME") or "TK Workbench"
if not r.ImGui_CreateContext then
  r.ShowMessageBox("ReaImGui is required for TK Workbench.", SCRIPT_NAME, 0)
  return
end

local script_path = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
local sep = package.config:sub(1, 1)
package.path = script_path .. "?.lua;" .. script_path .. "?" .. sep .. "init.lua;" .. package.path

local Settings = require("core.settings")
local Theme = require("core.theme")
local Selection = require("core.selection")
local ModuleLoader = require("core.module_loader")
local UI = require("core.ui")
local UIScale = require("core.ui_scale")

local ctx = r.ImGui_CreateContext(SCRIPT_NAME)
local config_name = rawget(_G, "TK_WORKBENCH_CONFIG_NAME") or "config.json"
local config_path = script_path .. config_name
local settings = Settings.load(config_path)
UIScale.set(settings.ui_scale)

local app = {
  ctx = ctx,
  script_name = SCRIPT_NAME,
  script_path = script_path,
  config_path = config_path,
  settings = settings,
  selection = {},
  modules = {},
  modules_by_id = {},
  module_errors = {},
  cache = {},
  status = "Ready",
  close_requested = false,
  settings_panel = nil
}
UI.configure_tooltips(app)
app.cache.saved_theme_preset = settings.theme_preset or "Graphite"

local HOME_MODULE_ID = "__home"
local MODULE_REORDER_PAYLOAD = "TK_WORKBENCH_MODULE_REORDER"
local MODULE_ACTION_EXT_SECTION = "TK_WORKBENCH_MODULE_ACTIONS"
local MODULE_ACTION_COMMAND_KEY = "command"
local MODULE_ACTION_RUNNING_KEY = "running"
local MODULE_ACTION_HEARTBEAT_KEY = "heartbeat"

local module_names = {
  "project_overview",
  "timepiece",
  "project_browser",
  "action_browser",
  "action_clipboard",
  "script_launcher",
  "track_recall",
  "track_tags",
  "automation_item_manager",
  "control_room",
  "instrument_rack",
  "fx_groups",
  "fx_chain_builder",
  "notes",
  "plugin_browser",
  "media_browser",
  "color_studio",
  "arrange_bg_presets",
  "calculator"
}

local theme_color_fields = {
  { key = "window_bg", label = "Window" },
  { key = "child_bg", label = "Panel" },
  { key = "popup_bg", label = "Popup" },
  { key = "frame_bg", label = "Frame" },
  { key = "frame_hover", label = "Frame Hover" },
  { key = "header", label = "Header" },
  { key = "header_hover", label = "Header Hover" },
  { key = "separator", label = "Separator" },
  { key = "border", label = "Border" },
  { key = "text", label = "Text" },
  { key = "text_dim", label = "Dim Text" },
  { key = "badge_text", label = "Badge Text" },
  { key = "accent", label = "Accent" },
  { key = "accent_soft", label = "Accent Soft" },
  { key = "warning", label = "Warning" },
  { key = "danger", label = "Danger" }
}

local ui_scale_options = {
  { label = "85%", value = 0.85 },
  { label = "100%", value = 1.0 },
  { label = "115%", value = 1.15 },
  { label = "130%", value = 1.3 },
  { label = "150%", value = 1.5 },
  { label = "175%", value = 1.75 },
  { label = "200%", value = 2.0 }
}

local function set_ui_scale(value)
  local scale = UIScale.set(value)
  app.settings.ui_scale = scale
  return scale
end

local function ui_scale_label(scale)
  scale = UIScale.normalize(scale)
  for _, option in ipairs(ui_scale_options) do
    if math.abs(scale - option.value) < 0.01 then return option.label end
  end
  return tostring(math.floor(scale * 100 + 0.5)) .. "%"
end

local function get_scaled_font()
  local scale = set_ui_scale(app.settings.ui_scale or 1.0)
  if math.abs(scale - 1.0) < 0.01 then return nil end
  if not r.ImGui_CreateFont then return nil end
  app.cache.ui_fonts = app.cache.ui_fonts or {}
  if app.cache.ui_font_ctx ~= ctx then
    app.cache.ui_fonts = {}
    app.cache.ui_font_ctx = ctx
  end
  local font_size = math.max(10, math.floor(13 * scale + 0.5))
  local key = tostring(font_size)
  if app.cache.ui_fonts[key] then return app.cache.ui_fonts[key], font_size end
  local ok, font = pcall(r.ImGui_CreateFont, "sans-serif", font_size)
  if not ok or not font then return nil end
  if r.ImGui_Attach then pcall(r.ImGui_Attach, ctx, font) end
  app.cache.ui_fonts[key] = font
  return font, font_size
end

local function push_scaled_font()
  local font, font_size = get_scaled_font()
  if not font or not r.ImGui_PushFont then return false end
  local ok = pcall(r.ImGui_PushFont, ctx, font, font_size)
  return ok == true
end

local function pop_scaled_font(pushed)
  if pushed and r.ImGui_PopFont then pcall(r.ImGui_PopFont, ctx) end
end

local function save_settings()
  Settings.save(config_path, app.settings)
end

app.save_settings = save_settings

local function append_error_log(key, err)
  local file = io.open(script_path .. "workbench_errors.txt", "a")
  if not file then return end
  file:write(os.date("%Y-%m-%d %H:%M:%S") .. " | " .. tostring(key) .. " | " .. tostring(err) .. "\n")
  file:close()
end

local function record_module_error(key, err)
  local message = tostring(err)
  if app.module_errors[key] ~= message then append_error_log(key, message) end
  app.module_errors[key] = message
end

local function clear_module_error(key)
  app.module_errors[key] = nil
end

app.record_module_error = record_module_error
app.clear_module_error = clear_module_error

local function find_module_index_by_id(id)
  for index, module in ipairs(app.modules) do
    if module.id == id then return index end
  end
  return nil
end

local function normalize_module_order()
  local loaded = {}
  for _, module in ipairs(app.modules) do loaded[module.id] = true end
  local order = type(app.settings.module_order) == "table" and app.settings.module_order or {}
  local normalized = {}
  local used = {}
  for _, id in ipairs(order) do
    if loaded[id] and not used[id] then
      normalized[#normalized + 1] = id
      used[id] = true
    end
  end
  for _, module in ipairs(app.modules) do
    if not used[module.id] then
      normalized[#normalized + 1] = module.id
      used[module.id] = true
    end
  end
  local changed = #normalized ~= #order
  if not changed then
    for index, id in ipairs(normalized) do
      if order[index] ~= id then changed = true; break end
    end
  end
  app.settings.module_order = normalized
  if changed then save_settings() end
  return normalized
end

local function save_module_order()
  local order = {}
  for _, module in ipairs(app.modules) do order[#order + 1] = module.id end
  app.settings.module_order = order
  save_settings()
end

local function apply_module_order()
  local order = normalize_module_order()
  local rank = {}
  for index, id in ipairs(order) do rank[id] = index end
  table.sort(app.modules, function(left, right)
    return (rank[left.id] or 9999) < (rank[right.id] or 9999)
  end)
end

local function move_module_to_target(source_id, target_id)
  if not source_id or not target_id or source_id == target_id then return false end
  local source_index = find_module_index_by_id(source_id)
  local target_index = find_module_index_by_id(target_id)
  if not source_index or not target_index then return false end
  local item = table.remove(app.modules, source_index)
  target_index = find_module_index_by_id(target_id) or target_index
  table.insert(app.modules, target_index, item)
  save_module_order()
  app.status = "Module order updated"
  return true
end

local function is_module_hidden(id)
  local hidden = app.settings.hidden_modules
  return type(hidden) == "table" and hidden[id] == true
end

local function set_module_hidden(id, hidden)
  local map = type(app.settings.hidden_modules) == "table" and app.settings.hidden_modules or {}
  if hidden then map[id] = true else map[id] = nil end
  app.settings.hidden_modules = map
  save_settings()
end

local function set_all_modules_hidden(hidden)
  local map = {}
  if hidden then
    for _, module in ipairs(app.modules) do map[module.id] = true end
  end
  app.settings.hidden_modules = map
  save_settings()
end

local function is_home_active()
  return app.settings.active_module == HOME_MODULE_ID
end

local function set_active_view(id)
  local current = app.settings.active_module
  if id == "plugin_browser" and current == "instrument_rack" then
    app.cache.plugin_browser_return_module = "instrument_rack"
  elseif id ~= "plugin_browser" then
    app.cache.plugin_browser_return_module = nil
  end
  app.settings.active_module = id
  save_settings()
end

app.set_active_view = set_active_view

local function open_horizontal_rack()
  local module = app.modules_by_id and app.modules_by_id.instrument_rack
  if module and module.launch_horizontal_rack then
    module.launch_horizontal_rack(app)
  else
    app.status = "Instrument Rack module not available"
  end
end

local HORIZONTAL_RACK_ENTRY = {
  id = "instrument_rack_horizontal",
  title = "Instrument Rack (H)",
  icon = "FX",
  synthetic = true,
  on_click = open_horizontal_rack,
}

local function horizontal_rack_entry_visible()
  return app.modules_by_id and app.modules_by_id.instrument_rack ~= nil and not is_module_hidden("instrument_rack")
end

local function process_module_action_commands()
  local command = r.GetExtState(MODULE_ACTION_EXT_SECTION, MODULE_ACTION_COMMAND_KEY) or ""
  if command == "" then return end
  r.SetExtState(MODULE_ACTION_EXT_SECTION, MODULE_ACTION_COMMAND_KEY, "", false)
  local action, target = command:match("^([%w_]+):(.+)$")
  if action ~= "open" or not target or target == "" then return end
  if target == HOME_MODULE_ID or app.modules_by_id[target] then
    set_active_view(target)
    local module = app.modules_by_id[target]
    app.status = "Opened " .. tostring(module and (module.title or module.id) or "Home")
  else
    app.status = "Workbench module not found: " .. tostring(target)
  end
end

local function get_active_module()
  local active_id = app.settings.active_module
  if active_id == HOME_MODULE_ID then return nil end
  if app.modules_by_id[active_id] then return app.modules_by_id[active_id] end
  if app.modules[1] then
    app.settings.active_module = app.modules[1].id
    save_settings()
    return app.modules[1]
  end
end

local function get_split_module()
  local active_id = app.settings.active_module
  local split_id = app.settings.split_module
  if split_id and split_id ~= "" and split_id ~= active_id and app.modules_by_id[split_id] then return app.modules_by_id[split_id] end
  for _, module in ipairs(app.modules) do
    if module.id ~= active_id then return module end
  end
end

local function split_view_available()
  return app.settings.split_view_enabled == true and not is_home_active() and get_active_module() ~= nil and get_split_module() ~= nil
end

local function split_orientation()
  return app.settings.split_orientation == "horizontal" and "horizontal" or "vertical"
end

local function set_split_module(id)
  if not id or id == "" or id == app.settings.active_module or not app.modules_by_id[id] then return false end
  app.settings.split_module = id
  app.settings.split_view_enabled = true
  app.status = "Split module: " .. tostring(app.modules_by_id[id].title or id)
  save_settings()
  return true
end

local function swap_split_modules()
  local split_module = get_split_module()
  local active_id = app.settings.active_module
  if not split_module or not active_id or active_id == HOME_MODULE_ID then return end
  app.settings.split_module = active_id
  set_active_view(split_module.id)
  app.settings.split_view_enabled = true
  app.status = "Split panes swapped"
  save_settings()
end

local function calc_text_width(value)
  if r.ImGui_CalcTextSize then
    local width = r.ImGui_CalcTextSize(ctx, tostring(value or ""))
    return tonumber(width) or 0
  end
  return #(tostring(value or "")) * 7
end

local function clamp(value, min_value, max_value)
  value = tonumber(value) or 0
  if value < min_value then return min_value end
  if value > max_value then return max_value end
  return value
end

local function split_rgba(color)
  color = math.floor(tonumber(color) or 0)
  if color < 0 then color = color + 0x100000000 end
  local red = math.floor(color / 0x1000000) % 0x100
  local green = math.floor(color / 0x10000) % 0x100
  local blue = math.floor(color / 0x100) % 0x100
  local alpha = color % 0x100
  return red, green, blue, alpha
end

local function rgba(red, green, blue, alpha)
  red = math.floor(clamp(red, 0, 255) + 0.5)
  green = math.floor(clamp(green, 0, 255) + 0.5)
  blue = math.floor(clamp(blue, 0, 255) + 0.5)
  alpha = math.floor(clamp(alpha or 255, 0, 255) + 0.5)
  return red * 0x1000000 + green * 0x10000 + blue * 0x100 + alpha
end

local function blend_color(first, second, amount)
  amount = clamp(amount, 0, 1)
  local ar, ag, ab, aa = split_rgba(first)
  local br, bg, bb, ba = split_rgba(second)
  return rgba(ar + (br - ar) * amount, ag + (bg - ag) * amount, ab + (bb - ab) * amount, aa + (ba - aa) * amount)
end

local function color_luminance(color)
  local red, green, blue = split_rgba(color)
  return (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255
end

local function contrast_from_background(background, amount)
  local target = color_luminance(background) > 0.5 and 0x000000FF or 0xFFFFFFFF
  return blend_color(background, target, amount)
end

local function ellipsize_text(value, max_width)
  value = tostring(value or "")
  if value == "" or calc_text_width(value) <= max_width then return value end
  while #value > 1 and calc_text_width(value .. "...") > max_width do value = value:sub(1, -2) end
  return value .. "..."
end

local function card_title_lines(title, max_width)
  local lines = { "", "" }
  local line_index = 1
  for token in tostring(title or ""):gmatch("%S+") do
    local candidate = lines[line_index] == "" and token or (lines[line_index] .. " " .. token)
    if calc_text_width(candidate) > max_width and lines[line_index] ~= "" then
      line_index = math.min(2, line_index + 1)
      candidate = lines[line_index] == "" and token or (lines[line_index] .. " " .. token)
    end
    lines[line_index] = candidate
  end
  lines[1] = ellipsize_text(lines[1], max_width)
  lines[2] = ellipsize_text(lines[2], max_width)
  return lines
end

local function fallback_icon_text(module)
  local icon = tostring(module and module.icon or "")
  if icon ~= "" then return icon end
  local text = tostring(module and (module.title or module.id) or "")
  local result = ""
  for token in text:gmatch("%S+") do result = result .. token:sub(1, 1):upper() end
  if result == "" then result = "?" end
  return result:sub(1, 3)
end

local function draw_home_icon(draw_list, x, y, size, color)
  local left = x + size * 0.2
  local right = x + size * 0.8
  local top = y + size * 0.25
  local mid = y + size * 0.48
  local bottom = y + size * 0.82
  r.ImGui_DrawList_AddLine(draw_list, left, mid, x + size * 0.5, top, color, 2)
  r.ImGui_DrawList_AddLine(draw_list, x + size * 0.5, top, right, mid, color, 2)
  r.ImGui_DrawList_AddRect(draw_list, left + 2, mid, right - 2, bottom, color, 2, 0, 2)
  r.ImGui_DrawList_AddLine(draw_list, x + size * 0.48, bottom, x + size * 0.48, y + size * 0.64, color, 2)
  r.ImGui_DrawList_AddLine(draw_list, x + size * 0.48, y + size * 0.64, x + size * 0.62, y + size * 0.64, color, 2)
  r.ImGui_DrawList_AddLine(draw_list, x + size * 0.62, y + size * 0.64, x + size * 0.62, bottom, color, 2)
end

local function draw_split_icon(draw_list, x, y, size, color)
  local left = x + size * 0.2
  local right = x + size * 0.8
  local top = y + size * 0.2
  local bottom = y + size * 0.8
  local mid = y + size * 0.5
  r.ImGui_DrawList_AddRect(draw_list, left, top, right, mid - 2, color, 2, 0, 2)
  r.ImGui_DrawList_AddRect(draw_list, left, mid + 2, right, bottom, color, 2, 0, 2)
end

local function draw_module_icon(draw_list, module, cx, cy, size, color)
  local id = module and module.id or ""
  local s = size / 48
  local left = cx - size * 0.5
  local right = cx + size * 0.5
  local top = cy - size * 0.5
  local bottom = cy + size * 0.5
  local function L(o) return left + o * s end
  local function R(o) return right - o * s end
  local function T(o) return top + o * s end
  local function B(o) return bottom - o * s end
  local function MX(o) return cx + (o or 0) * s end
  local function MY(o) return cy + (o or 0) * s end
  local function W(t) return math.max(1, (t or 1) * s) end
  local function RD(rd) return (rd or 1) * s end
  if id == "project_overview" then
    r.ImGui_DrawList_AddCircle(draw_list, cx, cy, size * 0.34, color, 32, W(2))
    r.ImGui_DrawList_AddCircleFilled(draw_list, cx, T(16), RD(2.2), color, 12)
    r.ImGui_DrawList_AddLine(draw_list, cx, MY(-2), cx, B(14), color, W(3))
    r.ImGui_DrawList_AddLine(draw_list, MX(-5), MY(-2), cx, MY(-2), color, W(3))
    r.ImGui_DrawList_AddLine(draw_list, MX(-5), B(14), MX(5), B(14), color, W(3))
  elseif id == "timepiece" then
    r.ImGui_DrawList_AddCircle(draw_list, cx, cy, size * 0.34, color, 32, W(2))
    r.ImGui_DrawList_AddCircleFilled(draw_list, cx, cy, RD(2.4), color, 12)
    r.ImGui_DrawList_AddLine(draw_list, cx, cy, cx, T(15), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, cx, cy, R(16), MY(7), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, cx, T(10), cx, T(14), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, cx, B(14), cx, B(10), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(10), cy, L(14), cy, color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, R(14), cy, R(10), cy, color, W(2))
  elseif id == "action_browser" then
    r.ImGui_DrawList_AddRect(draw_list, L(7), T(9), R(7), B(9), color, RD(4), 0, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(14), T(18), L(20), MY(-1), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(20), MY(-1), L(14), MY(8), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(25), MY(8), L(34), MY(8), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(14), B(17), R(16), B(17), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(14), B(10), R(24), B(10), color, W(2))
  elseif id == "action_clipboard" then
    r.ImGui_DrawList_AddRect(draw_list, L(9), T(10), R(9), B(5), color, RD(4), 0, W(2))
    r.ImGui_DrawList_AddRect(draw_list, MX(-10), T(5), MX(10), T(15), color, RD(4), 0, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(17), T(25), L(21), T(29), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(21), T(29), L(27), T(20), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(32), T(26), R(16), T(26), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(17), T(36), L(21), T(40), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(21), T(40), L(27), T(31), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(32), T(37), R(16), T(37), color, W(2))
  elseif id == "script_launcher" then
    r.ImGui_DrawList_AddRect(draw_list, L(7), T(8), R(7), B(8), color, RD(4), 0, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(17), T(16), L(17), B(16), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(17), T(16), R(16), cy, color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, R(16), cy, L(17), B(16), color, W(2))
  elseif id == "track_recall" then
    r.ImGui_DrawList_AddLine(draw_list, L(14), T(8), R(14), T(8), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(14), B(8), R(14), B(8), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(16), T(10), R(16), B(10), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, R(16), T(10), L(16), B(10), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(20), T(15), cx, MY(-2), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, R(20), T(15), cx, MY(-2), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, cx, MY(3), L(21), B(14), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, cx, MY(3), R(21), B(14), color, W(2))
  elseif id == "track_tags" then
    r.ImGui_DrawList_AddLine(draw_list, L(10), T(14), R(16), T(14), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, R(16), T(14), R(8), cy, color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, R(8), cy, R(16), B(14), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, R(16), B(14), L(10), B(14), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(10), B(14), L(10), T(14), color, W(2))
    r.ImGui_DrawList_AddCircleFilled(draw_list, L(18), cy, RD(3), color, 12)
    r.ImGui_DrawList_AddLine(draw_list, MX(-4), MY(-7), MX(9), MY(6), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, MX(3), MY(-7), MX(-4), cy, color, W(2))
  elseif id == "automation_item_manager" then
    r.ImGui_DrawList_AddLine(draw_list, L(6), B(12), MX(-8), MY(7), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, MX(-8), MY(7), MX(7), MY(-8), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, MX(7), MY(-8), R(7), T(14), color, W(2))
    r.ImGui_DrawList_AddCircleFilled(draw_list, L(6), B(12), RD(4), color, 12)
    r.ImGui_DrawList_AddCircleFilled(draw_list, MX(-8), MY(7), RD(4), color, 12)
    r.ImGui_DrawList_AddCircleFilled(draw_list, MX(7), MY(-8), RD(4), color, 12)
    r.ImGui_DrawList_AddCircleFilled(draw_list, R(7), T(14), RD(4), color, 12)
  elseif id == "control_room" then
    r.ImGui_DrawList_AddRect(draw_list, L(8), T(8), R(8), B(8), color, RD(4), 0, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(17), B(13), L(17), T(18), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, cx, B(13), cx, T(13), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, R(17), B(13), R(17), T(23), color, W(2))
    r.ImGui_DrawList_AddCircleFilled(draw_list, L(17), MY(6), RD(4), color, 12)
    r.ImGui_DrawList_AddCircleFilled(draw_list, cx, MY(-4), RD(4), color, 12)
    r.ImGui_DrawList_AddCircleFilled(draw_list, R(17), MY(10), RD(4), color, 12)
  elseif id == "instrument_rack" then
    r.ImGui_DrawList_AddRect(draw_list, L(7), T(8), R(7), B(8), color, RD(3), 0, W(2))
    for index = 0, 3 do
      local key_x = L(12 + index * 9)
      r.ImGui_DrawList_AddLine(draw_list, key_x, cy, key_x, B(10), color, W(2))
    end
    r.ImGui_DrawList_AddLine(draw_list, L(8), cy, R(8), cy, color, W(2))
  elseif id == "instrument_rack_horizontal" then
    r.ImGui_DrawList_AddRect(draw_list, L(8), T(7), R(8), B(7), color, RD(3), 0, W(2))
    for index = 0, 3 do
      local key_y = T(12 + index * 9)
      r.ImGui_DrawList_AddLine(draw_list, cx, key_y, R(10), key_y, color, W(2))
    end
    r.ImGui_DrawList_AddLine(draw_list, cx, T(8), cx, B(8), color, W(2))
  elseif id == "fx_chain_builder" then
    r.ImGui_DrawList_AddRect(draw_list, L(6), MY(-13), R(6), MY(13), color, RD(4), 0, W(2))
    r.ImGui_DrawList_AddRect(draw_list, L(10), MY(-6), L(20), MY(4), color, RD(2), 0, W(2))
    r.ImGui_DrawList_AddRect(draw_list, L(23), MY(-6), L(33), MY(4), color, RD(2), 0, W(2))
  elseif id == "fx_groups" then
    r.ImGui_DrawList_AddRect(draw_list, L(7), MY(-13), L(19), MY(-1), color, RD(3), 0, W(2))
    r.ImGui_DrawList_AddRect(draw_list, R(7), MY(1), R(19), MY(13), color, RD(3), 0, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(19), MY(-7), R(19), MY(7), color, W(2))
    r.ImGui_DrawList_AddCircleFilled(draw_list, L(19), MY(-7), RD(3), color, 12)
    r.ImGui_DrawList_AddCircleFilled(draw_list, R(19), MY(7), RD(3), color, 12)
  elseif id == "notes" then
    r.ImGui_DrawList_AddRect(draw_list, L(8), T(5), R(8), B(5), color, RD(4), 0, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(14), T(15), R(14), T(15), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(14), T(25), R(18), T(25), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(14), T(35), R(22), T(35), color, W(2))
  elseif id == "plugin_browser" then
    r.ImGui_DrawList_AddRect(draw_list, L(11), MY(-13), R(13), MY(13), color, RD(4), 0, W(2))
    r.ImGui_DrawList_AddLine(draw_list, R(13), MY(-6), R(6), MY(-6), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, R(13), MY(6), R(6), MY(6), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(6), cy, L(11), cy, color, W(2))
  elseif id == "media_browser" then
    r.ImGui_DrawList_AddRect(draw_list, L(6), T(9), R(6), B(9), color, RD(4), 0, W(2))
    for index = 0, 3 do
      local film_x = L(12 + index * 9)
      r.ImGui_DrawList_AddLine(draw_list, film_x, T(10), film_x, T(17), color, W(2))
      r.ImGui_DrawList_AddLine(draw_list, film_x, B(17), film_x, B(10), color, W(2))
    end
    r.ImGui_DrawList_AddLine(draw_list, L(14), cy, MX(-6), MY(-8), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, MX(-6), MY(-8), MX(6), MY(8), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, MX(6), MY(8), R(14), cy, color, W(2))
  elseif id == "arrange_bg_presets" then
    r.ImGui_DrawList_AddRect(draw_list, L(6), T(9), R(6), B(9), color, RD(3), 0, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(7), MY(-7), R(7), MY(-7), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(7), MY(4), R(7), MY(4), color, W(2))
    for index = 0, 2 do
      local grid_x = L(15 + index * 11)
      r.ImGui_DrawList_AddLine(draw_list, grid_x, T(12), grid_x, B(12), color, W(1))
    end
  elseif id == "calculator" then
    r.ImGui_DrawList_AddRect(draw_list, L(8), T(6), R(8), B(6), color, RD(3), 0, W(2))
    r.ImGui_DrawList_AddRect(draw_list, L(13), T(11), R(13), T(22), color, RD(2), 0, W(1))
    for by = 0, 1 do
      for bx = 0, 2 do
        r.ImGui_DrawList_AddCircleFilled(draw_list, L(17 + bx * 8), MY(7 + by * 9), RD(2), color, 10)
      end
    end
  else
    local icon = fallback_icon_text(module)
    r.ImGui_DrawList_AddCircle(draw_list, cx, cy, size * 0.34, color, 32, W(2))
    local text_w = calc_text_width(icon)
    r.ImGui_DrawList_AddText(draw_list, cx - text_w * 0.5, cy - r.ImGui_GetTextLineHeight(ctx) * 0.5, color, icon)
  end
end

local function draw_module_card(module, card_width, card_height)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local active = app.settings.active_module == module.id
  r.ImGui_PushID(ctx, module.id)
  local clicked = r.ImGui_InvisibleButton(ctx, "##home_module_card", card_width, card_height)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local x1, y1 = r.ImGui_GetItemRectMin(ctx)
  local x2, y2 = r.ImGui_GetItemRectMax(ctx)
  local bg = active and Theme.colors.accent_soft or (hovered and Theme.colors.frame_hover or Theme.colors.frame_bg)
  local border = active and Theme.colors.accent or Theme.colors.border
  local icon_color = Theme.text_for_background(bg, (hovered or active) and Theme.colors.accent or Theme.colors.text_dim, nil, 3)
  local title_color = Theme.text_for_background(bg, Theme.colors.text, nil, 4.5)
  local pad = UIScale.round(7)
  local icon_size = UIScale.round(48)
  r.ImGui_DrawList_AddRectFilled(draw_list, x1, y1, x2, y2, bg, UIScale.px(6))
  r.ImGui_DrawList_AddRect(draw_list, x1, y1, x2, y2, border, UIScale.px(6), 0, active and UIScale.px(1.6) or UIScale.px(0.8))
  draw_module_icon(draw_list, module, (x1 + x2) * 0.5, y1 + UIScale.round(36), icon_size, icon_color)
  local title = tostring(module.title or module.id or "Module")
  local lines = card_title_lines(title, card_width - pad * 2)
  local line_h = r.ImGui_GetTextLineHeight(ctx)
  local text_y = y2 - UIScale.round(12) - line_h * ((lines[2] ~= "" and 2 or 1))
  r.ImGui_DrawList_PushClipRect(draw_list, x1 + pad, y1 + UIScale.round(5), x2 - pad, y2 - UIScale.round(5), true)
  for index = 1, 2 do
    if lines[index] ~= "" then
      local text_w = calc_text_width(lines[index])
      r.ImGui_DrawList_AddText(draw_list, x1 + math.max(pad, (card_width - text_w) * 0.5), text_y + (index - 1) * line_h, title_color, lines[index])
    end
  end
  r.ImGui_DrawList_PopClipRect(draw_list)
  if not module.synthetic and r.ImGui_BeginDragDropSource and r.ImGui_SetDragDropPayload then
    local source_flags = r.ImGui_DragDropFlags_SourceNoPreviewTooltip and r.ImGui_DragDropFlags_SourceNoPreviewTooltip() or 0
    if r.ImGui_BeginDragDropSource(ctx, source_flags) then
      r.ImGui_SetDragDropPayload(ctx, MODULE_REORDER_PAYLOAD, module.id)
      r.ImGui_Text(ctx, title)
      r.ImGui_EndDragDropSource(ctx)
    end
  end
  if not module.synthetic and r.ImGui_BeginDragDropTarget and r.ImGui_AcceptDragDropPayload and r.ImGui_BeginDragDropTarget(ctx) then
    r.ImGui_DrawList_AddRect(draw_list, x1 + 2, y1 + 2, x2 - 2, y2 - 2, Theme.colors.accent, 6, 0, 2)
    local ok, payload = r.ImGui_AcceptDragDropPayload(ctx, MODULE_REORDER_PAYLOAD)
    if ok and payload and payload ~= module.id then app.cache.pending_module_reorder = { source = payload, target = module.id } end
    r.ImGui_EndDragDropTarget(ctx)
  end
  if clicked then
    if module.on_click then module.on_click() else set_active_view(module.id) end
  end
  if hovered then r.ImGui_SetTooltip(ctx, title .. (module.synthetic and "" or "\nDrag to reorder")) end
  r.ImGui_PopID(ctx)
end

local function draw_home_view()
  local _, available_h = r.ImGui_GetContentRegionAvail(ctx)
  local status_h = app.settings.show_status and UI.info_line_height(ctx) or 0
  local content_h = math.max(40, (available_h or 240) - status_h)
  local child_visible = r.ImGui_BeginChild(ctx, "##home_module_tiles", 0, content_h, 0)
  if child_visible then
    local avail_w = r.ImGui_GetContentRegionAvail(ctx) or 1
    local gap = UIScale.gap(10)
    local min_card_w = UIScale.round(118)
    local columns = math.max(1, math.floor((avail_w + gap) / (min_card_w + gap)))
    local card_w = math.max(1, math.floor((avail_w - gap * (columns - 1)) / columns))
    while columns > 1 and card_w < min_card_w do
      columns = columns - 1
      card_w = math.max(1, math.floor((avail_w - gap * (columns - 1)) / columns))
    end
    local card_h = math.max(UIScale.round(104), math.ceil(r.ImGui_GetTextLineHeight(ctx) * 5.8))
    local visible_index = 0
    for _, module in ipairs(app.modules) do
      if not is_module_hidden(module.id) then
        visible_index = visible_index + 1
        draw_module_card(module, card_w, card_h)
        if visible_index % columns ~= 0 then r.ImGui_SameLine(ctx, 0, gap) end
      end
    end
    if horizontal_rack_entry_visible() then
      visible_index = visible_index + 1
      draw_module_card(HORIZONTAL_RACK_ENTRY, card_w, card_h)
      if visible_index % columns ~= 0 then r.ImGui_SameLine(ctx, 0, gap) end
    end
    local pending = app.cache.pending_module_reorder
    if pending then
      app.cache.pending_module_reorder = nil
      move_module_to_target(pending.source, pending.target)
    end
  end
  r.ImGui_EndChild(ctx)
end

local function draw_top_bar()
  local avail_w = r.ImGui_GetContentRegionAvail(ctx)
  local active_module = get_active_module()
  local title = is_home_active() and "Home" or tostring(active_module and (active_module.title or active_module.id) or "Module")
  local dot_size = UIScale.round(14)
  local dot_gap = UIScale.gap(8)
  local dot_unit = dot_size / 14
  r.ImGui_TextColored(ctx, Theme.colors.accent, SCRIPT_NAME)
  r.ImGui_SameLine(ctx, math.max(UIScale.round(120), avail_w - (dot_size * 3) - (dot_gap * 2)))
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local pin_x, pin_y = r.ImGui_GetCursorScreenPos(ctx)
  local pin_active = app.settings.auto_collapse_keep_expanded == true
  local pin_color = pin_active and Theme.colors.accent or Theme.colors.text_dim
  r.ImGui_DrawList_AddCircleFilled(draw_list, pin_x + dot_size * 0.5, pin_y + dot_size * 0.5, dot_size * 0.5, pin_active and Theme.colors.accent_soft or Theme.colors.frame_bg)
  r.ImGui_DrawList_AddCircle(draw_list, pin_x + dot_size * 0.5, pin_y + dot_size * 0.5, dot_size * 0.5, pin_active and Theme.colors.accent or Theme.colors.border, 16, 1)
  r.ImGui_DrawList_AddLine(draw_list, pin_x + 5 * dot_unit, pin_y + 4 * dot_unit, pin_x + 9 * dot_unit, pin_y + 4 * dot_unit, pin_color, UIScale.px(1.5))
  r.ImGui_DrawList_AddLine(draw_list, pin_x + 7 * dot_unit, pin_y + 4 * dot_unit, pin_x + 7 * dot_unit, pin_y + 10 * dot_unit, pin_color, UIScale.px(1.5))
  r.ImGui_DrawList_AddLine(draw_list, pin_x + 5 * dot_unit, pin_y + 10 * dot_unit, pin_x + 9 * dot_unit, pin_y + 10 * dot_unit, pin_color, UIScale.px(1.5))
  if r.ImGui_InvisibleButton(ctx, "##workbench_keep_expanded_pin", dot_size, dot_size) then
    app.settings.auto_collapse_keep_expanded = not pin_active
    if app.settings.auto_collapse_keep_expanded then
      app.cache.auto_collapse_collapsed = false
      app.cache.auto_collapse_force_restore = true
      app.status = "Workbench pinned open"
    else
      app.cache.auto_collapse_last_hover_time = r.time_precise and r.time_precise() or os.clock()
      app.status = "Workbench auto-collapse active"
    end
    save_settings()
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, pin_active and "Allow auto-collapse" or "Keep Workbench expanded") end
  r.ImGui_SameLine(ctx, 0, dot_gap)
  local settings_x, settings_y = r.ImGui_GetCursorScreenPos(ctx)
  local dot_y = settings_y + dot_size * 0.5
  r.ImGui_DrawList_AddCircleFilled(draw_list, settings_x + dot_size * 0.5, dot_y, dot_size * 0.5, 0xF2F2F2FF)
  r.ImGui_DrawList_AddCircle(draw_list, settings_x + dot_size * 0.5, dot_y, dot_size * 0.5, 0x8F9AA8FF, 16, 1)
  if r.ImGui_InvisibleButton(ctx, "##workbench_settings_dot", dot_size, dot_size) then
    app.settings_panel = "preferences"
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Settings") end
  r.ImGui_SameLine(ctx, 0, dot_gap)
  local close_x, close_y = r.ImGui_GetCursorScreenPos(ctx)
  local close_y_mid = close_y + dot_size * 0.5
  r.ImGui_DrawList_AddCircleFilled(draw_list, close_x + dot_size * 0.5, close_y_mid, dot_size * 0.5, 0xF7768EFF)
  r.ImGui_DrawList_AddCircle(draw_list, close_x + dot_size * 0.5, close_y_mid, dot_size * 0.5, 0x3A1018FF, 16, 1)
  if r.ImGui_InvisibleButton(ctx, "##workbench_close_dot", dot_size, dot_size) then app.close_requested = true end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Close") end
  local home_size = r.ImGui_GetFrameHeight(ctx)
  local home_x, home_y = r.ImGui_GetCursorScreenPos(ctx)
  if r.ImGui_InvisibleButton(ctx, "##tk_workbench_home", home_size, home_size) then set_active_view(HOME_MODULE_ID) end
  local home_hovered = r.ImGui_IsItemHovered(ctx)
  local home_color = (is_home_active() or home_hovered) and Theme.colors.accent or Theme.colors.text_dim
  r.ImGui_DrawList_AddRectFilled(draw_list, home_x, home_y, home_x + home_size, home_y + home_size, is_home_active() and Theme.colors.accent_soft or Theme.colors.frame_bg, UIScale.px(4))
  r.ImGui_DrawList_AddRect(draw_list, home_x, home_y, home_x + home_size, home_y + home_size, home_hovered and Theme.colors.accent or Theme.colors.border, UIScale.px(4), 0, UIScale.px(1))
  local icon_inset = UIScale.round(3)
  draw_home_icon(draw_list, home_x + icon_inset, home_y + icon_inset, home_size - icon_inset * 2, home_color)
  if home_hovered then r.ImGui_SetTooltip(ctx, "Home") end
  r.ImGui_SameLine(ctx, 0, UIScale.gap(6))
  local split_x, split_y = r.ImGui_GetCursorScreenPos(ctx)
  if r.ImGui_InvisibleButton(ctx, "##tk_workbench_split", home_size, home_size) then r.ImGui_OpenPopup(ctx, "##tk_workbench_split_menu") end
  local split_hovered = r.ImGui_IsItemHovered(ctx)
  local split_active = split_view_available()
  local split_color = (split_active or split_hovered) and Theme.colors.accent or Theme.colors.text_dim
  r.ImGui_DrawList_AddRectFilled(draw_list, split_x, split_y, split_x + home_size, split_y + home_size, split_active and Theme.colors.accent_soft or Theme.colors.frame_bg, UIScale.px(4))
  r.ImGui_DrawList_AddRect(draw_list, split_x, split_y, split_x + home_size, split_y + home_size, split_hovered and Theme.colors.accent or Theme.colors.border, UIScale.px(4), 0, UIScale.px(1))
  draw_split_icon(draw_list, split_x + icon_inset, split_y + icon_inset, home_size - icon_inset * 2, split_color)
  if split_hovered then r.ImGui_SetTooltip(ctx, "Split view") end
  if r.ImGui_BeginPopup(ctx, "##tk_workbench_split_menu") then
    local enabled = app.settings.split_view_enabled == true
    local changed, value = r.ImGui_Checkbox(ctx, "Split View", enabled)
    if changed then
      app.settings.split_view_enabled = value
      app.status = value and "Split view enabled" or "Split view disabled"
      save_settings()
    end
    r.ImGui_Separator(ctx)
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Secondary")
    for _, candidate in ipairs(app.modules) do
      if candidate.id ~= app.settings.active_module and not is_module_hidden(candidate.id) then
        local selected = app.settings.split_module == candidate.id
        if r.ImGui_Selectable(ctx, candidate.title or candidate.id, selected) then set_split_module(candidate.id) end
        if selected then r.ImGui_SetItemDefaultFocus(ctx) end
      end
    end
    r.ImGui_Separator(ctx)
    local is_horizontal = split_orientation() == "horizontal"
    if r.ImGui_MenuItem(ctx, "Side by side", nil, is_horizontal) then
      app.settings.split_orientation = is_horizontal and "vertical" or "horizontal"
      app.status = is_horizontal and "Split stacked" or "Split side by side"
      save_settings()
    end
    if r.ImGui_MenuItem(ctx, "Swap panes", nil, false, split_view_available()) then swap_split_modules() end
    if r.ImGui_MenuItem(ctx, "Close split", nil, false, enabled) then
      app.settings.split_view_enabled = false
      app.status = "Split view disabled"
      save_settings()
    end
    r.ImGui_EndPopup(ctx)
  end
  r.ImGui_SameLine(ctx, 0, UIScale.gap(6))
  local combo_flags = r.ImGui_ComboFlags_HeightLargest and r.ImGui_ComboFlags_HeightLargest() or 0
  r.ImGui_PushItemWidth(ctx, -1)
  if r.ImGui_BeginCombo(ctx, "##tk_workbench_module_select", title, combo_flags) then
    for _, candidate in ipairs(app.modules) do
      if not is_module_hidden(candidate.id) or app.settings.active_module == candidate.id then
        local selected = app.settings.active_module == candidate.id
        if r.ImGui_Selectable(ctx, candidate.title or candidate.id, selected) then
          set_active_view(candidate.id)
        end
        if selected then r.ImGui_SetItemDefaultFocus(ctx) end
      end
    end
    if horizontal_rack_entry_visible() then
      if r.ImGui_Selectable(ctx, HORIZONTAL_RACK_ENTRY.title, false) then
        open_horizontal_rack()
      end
    end
    r.ImGui_EndCombo(ctx)
  end
  r.ImGui_PopItemWidth(ctx)
  r.ImGui_Separator(ctx)
end

local function draw_theme_preview(colors)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local size = UIScale.round(18)
  local gap = UIScale.gap(6)
  local swatches = { colors.window_bg, colors.child_bg, colors.frame_bg, colors.accent, colors.warning, colors.danger }
  for index, color in ipairs(swatches) do
    local left = x + (index - 1) * (size + gap)
    r.ImGui_DrawList_AddRectFilled(draw_list, left, y, left + size, y + size, color, UIScale.px(3))
    r.ImGui_DrawList_AddRect(draw_list, left, y, left + size, y + size, Theme.colors.border, UIScale.px(3), 0, UIScale.px(1))
  end
  r.ImGui_Dummy(ctx, (#swatches * (size + gap)) - gap, size)
end

local function trim_text(value)
  return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

local function is_reserved_theme_name(name)
  local normalized = trim_text(name):lower()
  if normalized == "unsaved custom" then return true end
  if Theme.is_reserved_preset_name and Theme.is_reserved_preset_name(normalized) then return true end
  for preset_name in pairs(Theme.presets or {}) do
    if preset_name:lower() == normalized then return true end
  end
  return false
end

local function draw_theme_settings_body()
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Preset")
    local current = app.settings.theme_preset or "Graphite"
    if r.ImGui_BeginCombo(ctx, "##theme_preset", current) then
      for _, name in ipairs(Theme.get_preset_names()) do
        local selected = current == name
        if r.ImGui_Selectable(ctx, name, selected) then
          app.settings.theme_preset = Theme.set_preset(name, app.settings.custom_themes)
          app.cache.saved_theme_preset = app.settings.theme_preset
          app.status = "Theme preset: " .. app.settings.theme_preset
          save_settings()
        end
        if selected then r.ImGui_SetItemDefaultFocus(ctx) end
      end
      if next(app.settings.custom_themes or {}) then r.ImGui_Separator(ctx) end
      local custom_names = {}
      for name in pairs(app.settings.custom_themes or {}) do custom_names[#custom_names + 1] = name end
      table.sort(custom_names)
      for _, name in ipairs(custom_names) do
        local selected = current == name
        if r.ImGui_Selectable(ctx, name .. "##custom_theme", selected) then
          app.settings.theme_preset = Theme.set_preset(name, app.settings.custom_themes)
          app.settings.custom_theme_name = name
          app.cache.saved_theme_preset = app.settings.theme_preset
          app.status = "Theme preset: " .. app.settings.theme_preset
          save_settings()
        end
        if selected then r.ImGui_SetItemDefaultFocus(ctx) end
      end
      r.ImGui_EndCombo(ctx)
    end
    if Theme.is_reaper_theme_preset and Theme.is_reaper_theme_preset(current) then
      if r.ImGui_Button(ctx, "Refresh REAPER Theme", UIScale.text_button_w(ctx, "Refresh REAPER Theme", 160, 8), UIScale.button_h(ctx, 24)) then
        app.settings.theme_preset = Theme.set_preset(current, app.settings.custom_themes)
        app.cache.saved_theme_preset = app.settings.theme_preset
        app.status = "REAPER theme colors refreshed"
        save_settings()
      end
      if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Read colors from the active REAPER theme") end
    end
    r.ImGui_Separator(ctx)
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Preview")
    draw_theme_preview(Theme.colors)
    r.ImGui_Spacing(ctx)
    local child_visible = r.ImGui_BeginChild(ctx, "##theme_color_editor", UIScale.round(330), UIScale.round(190), 1)
    if child_visible then
      local color_flags = r.ImGui_ColorEditFlags_NoInputs()
      for _, field in ipairs(theme_color_fields) do
        local changed, value = r.ImGui_ColorEdit4(ctx, field.label .. "##" .. field.key, Theme.colors[field.key], color_flags)
        if changed then
          Theme.colors[field.key] = value
          app.settings.theme_preset = "Unsaved Custom"
          Theme.set_colors(Theme.colors, app.settings.theme_preset)
        end
      end
    end
    r.ImGui_EndChild(ctx)
    r.ImGui_TextWrapped(ctx, "Theme changes are applied immediately. Custom themes load from the preset dropdown.")
    local name_changed, new_name = r.ImGui_InputTextWithHint(ctx, "##custom_theme_name", "Custom theme name", app.settings.custom_theme_name or "My Theme")
    if name_changed then app.settings.custom_theme_name = new_name end
    local theme_name = trim_text(app.settings.custom_theme_name or "")
    local theme_exists = app.settings.custom_themes and app.settings.custom_themes[theme_name] ~= nil
    local save_label = theme_exists and "Update Custom##save_custom_theme" or "Save Custom##save_custom_theme"
    if r.ImGui_Button(ctx, save_label, 110, 24) then
      if theme_name == "" then
        app.status = "Custom theme name required"
      elseif is_reserved_theme_name(theme_name) then
        app.status = "Reserved theme names cannot be overwritten"
      else
        local existed = app.settings.custom_themes and app.settings.custom_themes[theme_name] ~= nil
        app.settings.custom_theme_name = theme_name
        app.settings.custom_themes = app.settings.custom_themes or {}
        app.settings.custom_themes[theme_name] = Theme.copy_current_colors()
        app.settings.theme_preset = theme_name
        Theme.set_preset(theme_name, app.settings.custom_themes)
        app.cache.saved_theme_preset = app.settings.theme_preset
        app.status = (existed and "Updated custom theme: " or "Saved custom theme: ") .. theme_name
        save_settings()
      end
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, theme_exists and "Update existing custom theme" or "Save current colors as custom theme") end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Delete Custom", 110, 24) then
      if theme_name == "" then
        app.status = "Custom theme name required"
      elseif is_reserved_theme_name(theme_name) then
        app.status = "Reserved themes cannot be deleted"
      elseif app.settings.custom_themes and app.settings.custom_themes[theme_name] then
        app.settings.custom_themes[theme_name] = nil
        app.settings.custom_theme_name = theme_name
        if app.settings.theme_preset == theme_name then
          app.settings.theme_preset = Theme.set_preset("Graphite", app.settings.custom_themes)
          app.cache.saved_theme_preset = app.settings.theme_preset
        end
        app.status = "Deleted custom theme: " .. theme_name
        save_settings()
      else
        app.status = "Custom theme not found: " .. theme_name
      end
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Delete custom theme by name") end
    r.ImGui_Separator(ctx)
    if r.ImGui_Button(ctx, "Reset", UIScale.text_button_w(ctx, "Reset", 90, 8), UIScale.button_h(ctx, 24)) then
      app.settings.theme_preset = Theme.set_preset("Graphite", app.settings.custom_themes)
      app.cache.saved_theme_preset = app.settings.theme_preset
      app.status = "Theme preset reset"
      save_settings()
    end
end

local function draw_preferences_tab(label, tab_id)
  local current = app.cache.preferences_tab or "general"
  local active = current == tab_id
  local pad_x = UIScale.round(10)
  local pad_y = UIScale.round(4)
  local h = r.ImGui_GetTextLineHeight(ctx) + pad_y * 2
  local w = calc_text_width(label) + pad_x * 2
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local clicked = r.ImGui_InvisibleButton(ctx, "##pref_tab_" .. tab_id, w, h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local bg = active and Theme.colors.accent_soft or (hovered and Theme.colors.frame_hover or Theme.colors.frame_bg)
  local border = active and Theme.colors.accent or Theme.colors.border
  local text_color = active and Theme.colors.accent or Theme.colors.text
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + w, y + h, bg, UIScale.px(4))
  r.ImGui_DrawList_AddRect(draw_list, x, y, x + w, y + h, border, UIScale.px(4), 0, UIScale.px(1))
  r.ImGui_DrawList_AddText(draw_list, x + pad_x, y + pad_y, text_color, label)
  if clicked then app.cache.preferences_tab = tab_id end
end

local function draw_preferences_settings()
  if app.settings_panel == "preferences" then
    app.cache.preferences_open = true
    app.settings_panel = nil
  elseif app.settings_panel == "theme" then
    app.cache.preferences_open = true
    app.cache.preferences_tab = "theme"
    app.settings_panel = nil
  end
  if not app.cache.preferences_open then return end
  local visible, open = r.ImGui_Begin(ctx, "Preferences##tk_workbench_preferences", true, r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_NoCollapse() | r.ImGui_WindowFlags_AlwaysAutoResize())
  app.cache.preferences_open = open
  if visible then
    r.ImGui_TextColored(ctx, Theme.colors.accent, "Preferences")
    local close_size = UIScale.round(14)
    r.ImGui_SameLine(ctx, math.max(UIScale.round(140), r.ImGui_GetWindowWidth(ctx) - close_size - UIScale.round(16)))
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local close_x, close_y = r.ImGui_GetCursorScreenPos(ctx)
    r.ImGui_DrawList_AddCircleFilled(draw_list, close_x + close_size * 0.5, close_y + close_size * 0.5, close_size * 0.5, 0xF7768EFF)
    r.ImGui_DrawList_AddCircle(draw_list, close_x + close_size * 0.5, close_y + close_size * 0.5, close_size * 0.5, 0x3A1018FF, 16, UIScale.px(1))
    if r.ImGui_InvisibleButton(ctx, "##preferences_close", close_size, close_size) then app.cache.preferences_open = false end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Close") end
    r.ImGui_Separator(ctx)
    local pref_tabs = { { id = "general", label = "General" }, { id = "modules", label = "Modules" }, { id = "theme", label = "Theme" } }
    for index, tab in ipairs(pref_tabs) do
      draw_preferences_tab(tab.label, tab.id)
      if index < #pref_tabs then r.ImGui_SameLine(ctx, 0, UIScale.gap(6)) end
    end
    r.ImGui_Separator(ctx)
    local active_tab = app.cache.preferences_tab or "general"
    if active_tab ~= app.cache.preferences_tab_applied then
      if active_tab == "theme" and Theme.is_reaper_theme_preset and Theme.is_reaper_theme_preset(app.settings.theme_preset) then
        Theme.set_preset(app.settings.theme_preset, app.settings.custom_themes)
      end
      app.cache.preferences_tab_applied = active_tab
    end
    if active_tab == "theme" then
      draw_theme_settings_body()
      r.ImGui_End(ctx)
      return
    end
    if active_tab == "modules" then
      r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Show or hide modules in the tiles and dropdown.")
      if r.ImGui_SmallButton(ctx, "Show all") then
        set_all_modules_hidden(false)
        app.status = "All modules visible"
      end
      r.ImGui_SameLine(ctx, 0, UIScale.gap(6))
      if r.ImGui_SmallButton(ctx, "Hide all") then
        set_all_modules_hidden(true)
        app.status = "All modules hidden"
      end
      r.ImGui_Separator(ctx)
      for _, module in ipairs(app.modules) do
        local module_visible = not is_module_hidden(module.id)
        local changed, value = r.ImGui_Checkbox(ctx, (module.title or module.id) .. "##pref_module_" .. module.id, module_visible)
        if changed then
          set_module_hidden(module.id, not value)
          app.status = value and ((module.title or module.id) .. " shown") or ((module.title or module.id) .. " hidden")
        end
      end
      r.ImGui_End(ctx)
      return
    end
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "UI scale")
    r.ImGui_PushItemWidth(ctx, 140)
    local current_scale = set_ui_scale(app.settings.ui_scale or 1.0)
    if r.ImGui_BeginCombo(ctx, "##workbench_ui_scale", ui_scale_label(current_scale)) then
      for _, option in ipairs(ui_scale_options) do
        local selected = math.abs(current_scale - option.value) < 0.01
        if r.ImGui_Selectable(ctx, option.label, selected) then
          set_ui_scale(option.value)
          app.cache.ui_fonts = {}
          app.status = "UI scale: " .. option.label
          save_settings()
        end
        if selected then r.ImGui_SetItemDefaultFocus(ctx) end
      end
      r.ImGui_EndCombo(ctx)
    end
    r.ImGui_PopItemWidth(ctx)
    r.ImGui_Separator(ctx)
    r.ImGui_PushItemWidth(ctx, UIScale.round(160))
    local alpha_pct = math.floor((app.settings.window_bg_alpha or 1.0) * 100 + 0.5)
    local alpha_changed, alpha_value = r.ImGui_SliderInt(ctx, "Background opacity", alpha_pct, 20, 100, "%d%%")
    if alpha_changed then
      app.settings.window_bg_alpha = math.max(0.2, math.min(1.0, alpha_value / 100))
      app.status = string.format("Background opacity: %d%%", alpha_value)
      save_settings()
    end
    r.ImGui_PopItemWidth(ctx)
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Lowers the main panel background opacity (floating window).")
    r.ImGui_PushItemWidth(ctx, UIScale.round(160))
    local child_pct = math.floor((app.settings.child_bg_alpha or 1.0) * 100 + 0.5)
    local child_changed, child_value = r.ImGui_SliderInt(ctx, "Module panel opacity", child_pct, 20, 100, "%d%%")
    if child_changed then
      app.settings.child_bg_alpha = math.max(0.2, math.min(1.0, child_value / 100))
      app.status = string.format("Module panel opacity: %d%%", child_value)
      save_settings()
    end
    r.ImGui_PopItemWidth(ctx)
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Lowers the module panel background opacity.")
    r.ImGui_Separator(ctx)
    local changed, value = r.ImGui_Checkbox(ctx, "Hide scrollbars", app.settings.hide_scrollbars == true)
    if changed then
      app.settings.hide_scrollbars = value
      app.status = value and "Scrollbars hidden" or "Scrollbars visible"
      save_settings()
    end
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Scroll wheel remains active.")
    r.ImGui_Separator(ctx)
    changed, value = r.ImGui_Checkbox(ctx, "Info box", app.settings.show_status ~= false)
    if changed then
      app.settings.show_status = value
      app.status = value and "Info box visible" or "Info box hidden"
      save_settings()
    end
    r.ImGui_Separator(ctx)
    local auto_collapse_locked = app.cache.window_docked == true
    local auto_collapse_disabled_stack = auto_collapse_locked and r.ImGui_BeginDisabled and r.ImGui_EndDisabled
    if auto_collapse_disabled_stack then r.ImGui_BeginDisabled(ctx, true) end
    changed, value = r.ImGui_Checkbox(ctx, "Auto-collapse", app.settings.auto_collapse == true)
    if changed and not auto_collapse_locked then
      app.settings.auto_collapse = value
      app.cache.auto_collapse_collapsed = false
      app.cache.auto_collapse_force_restore = true
      app.status = value and "Auto-collapse enabled" or "Auto-collapse disabled"
      save_settings()
    end
    local side = app.settings.auto_collapse_side == "right" and "Right" or "Left"
    r.ImGui_PushItemWidth(ctx, 140)
    if r.ImGui_BeginCombo(ctx, "Lock side", side) then
      if r.ImGui_Selectable(ctx, "Left", side == "Left") and not auto_collapse_locked then
        app.settings.auto_collapse_side = "left"
        app.cache.auto_collapse_force_restore = true
        app.status = "Auto-collapse lock: left"
        save_settings()
      end
      if r.ImGui_Selectable(ctx, "Right", side == "Right") and not auto_collapse_locked then
        app.settings.auto_collapse_side = "right"
        app.cache.auto_collapse_force_restore = true
        app.status = "Auto-collapse lock: right"
        save_settings()
      end
      r.ImGui_EndCombo(ctx)
    end
    r.ImGui_PopItemWidth(ctx)
    r.ImGui_PushItemWidth(ctx, 140)
    changed, value = r.ImGui_SliderInt(ctx, "Edge offset", math.floor((tonumber(app.settings.auto_collapse_edge_offset) or 0) + 0.5), 0, 96, "%d px")
    if changed and not auto_collapse_locked then
      app.settings.auto_collapse_edge_offset = value
      app.cache.auto_collapse_force_restore = true
      app.status = "Auto-collapse edge offset: " .. tostring(value) .. " px"
      save_settings()
    end
    r.ImGui_PopItemWidth(ctx)
    r.ImGui_PushItemWidth(ctx, 140)
    changed, value = r.ImGui_SliderDouble(ctx, "Close delay", tonumber(app.settings.auto_collapse_delay) or 0.6, 0.1, 5.0, "%.1f s")
    if changed and not auto_collapse_locked then
      app.settings.auto_collapse_delay = value
      app.cache.auto_collapse_last_hover_time = r.time_precise and r.time_precise() or os.clock()
      app.status = "Auto-collapse close delay: " .. string.format("%.1f", value) .. " s"
      save_settings()
    end
    r.ImGui_PopItemWidth(ctx)
    local height_mode = app.settings.auto_collapse_height_mode
    local height_label = "Manual"
    if height_mode == "arrange" then height_label = "Arrange" end
    if height_mode == "reaper" then height_label = "REAPER window" end
    if height_mode == "arrange_window" then height_label = "Arrange to bottom" end
    r.ImGui_PushItemWidth(ctx, 140)
    if r.ImGui_BeginCombo(ctx, "Auto height", height_label) then
      if r.ImGui_Selectable(ctx, "Manual", height_label == "Manual") and not auto_collapse_locked then
        app.settings.auto_collapse_height_mode = "manual"
        app.cache.auto_collapse_force_restore = true
        app.status = "Auto height: manual"
        save_settings()
      end
      if r.ImGui_Selectable(ctx, "Arrange", height_label == "Arrange") and not auto_collapse_locked then
        app.settings.auto_collapse_height_mode = "arrange"
        app.cache.auto_collapse_force_restore = true
        app.status = "Auto height: arrange"
        save_settings()
      end
      if r.ImGui_Selectable(ctx, "REAPER window", height_label == "REAPER window") and not auto_collapse_locked then
        app.settings.auto_collapse_height_mode = "reaper"
        app.cache.auto_collapse_force_restore = true
        app.status = "Auto height: REAPER window"
        save_settings()
      end
      if r.ImGui_Selectable(ctx, "Arrange to bottom", height_label == "Arrange to bottom") and not auto_collapse_locked then
        app.settings.auto_collapse_height_mode = "arrange_window"
        app.cache.auto_collapse_force_restore = true
        app.status = "Auto height: arrange to bottom"
        save_settings()
      end
      r.ImGui_EndCombo(ctx)
    end
    r.ImGui_PopItemWidth(ctx)
    if auto_collapse_disabled_stack then r.ImGui_EndDisabled(ctx) end
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, auto_collapse_locked and "Auto-collapse is inactive while Workbench is docked." or "Floating Workbench windows only.")
    r.ImGui_Separator(ctx)
    changed, value = r.ImGui_Checkbox(ctx, "Tooltips", app.settings.tooltips_enabled ~= false)
    if changed then
      app.settings.tooltips_enabled = value
      app.cache.tooltip = nil
      app.status = value and "Tooltips enabled" or "Tooltips disabled"
      save_settings()
    end
    local delays = {
      { label = "Direct", value = 0 },
      { label = "0.5 seconds", value = 0.5 },
      { label = "1 second", value = 1.0 },
      { label = "2 seconds", value = 2.0 },
      { label = "3 seconds", value = 3.0 }
    }
    local current_delay = tonumber(app.settings.tooltip_delay) or 1.0
    local current_label = "1 second"
    for _, option in ipairs(delays) do
      if math.abs(current_delay - option.value) < 0.01 then current_label = option.label; break end
    end
    r.ImGui_PushItemWidth(ctx, 140)
    if r.ImGui_BeginCombo(ctx, "Tooltip delay", current_label) then
      for _, option in ipairs(delays) do
        local selected = math.abs(current_delay - option.value) < 0.01
        if r.ImGui_Selectable(ctx, option.label, selected) then
          app.settings.tooltip_delay = option.value
          app.cache.tooltip = nil
          app.status = option.value <= 0 and "Tooltips show directly" or ("Tooltip delay: " .. option.label)
          save_settings()
        end
        if selected then r.ImGui_SetItemDefaultFocus(ctx) end
      end
      r.ImGui_EndCombo(ctx)
    end
    r.ImGui_PopItemWidth(ctx)
  end
  r.ImGui_End(ctx)
end

local function current_time()
  return r.time_precise and r.time_precise() or os.clock()
end
local function auto_collapse_side()
  return app.settings.auto_collapse_side == "right" and "right" or "left"
end

local function auto_collapse_width()
  return clamp(app.settings.auto_collapse_width or 1, 1, 1)
end

local function auto_collapse_delay()
  return clamp(app.settings.auto_collapse_delay or 0.6, 0.1, 5.0)
end

local function auto_collapse_edge_hover_margin()
  return clamp(app.settings.auto_collapse_edge_hover_margin or 12, 0, 32)
end

local function auto_collapse_edge_offset()
  return clamp(app.settings.auto_collapse_edge_offset or 0, 0, 96)
end

local function expanded_window_min_size()
  return UIScale.round(260), UIScale.round(240)
end

local function auto_collapse_height_mode()
  local mode = app.settings.auto_collapse_height_mode
  if mode == "arrange" or mode == "reaper" or mode == "arrange_window" then return mode end
  return "manual"
end

local function auto_collapse_target_rect(mode)
  if not r.GetMainHwnd then return nil end
  local hwnd = r.GetMainHwnd()
  if not hwnd then return nil end
  local ok, left, top, right, bottom
  if mode == "arrange" then
    if not r.JS_Window_FindChildByID or not r.JS_Window_GetRect then return nil end
    local arrange = r.JS_Window_FindChildByID(hwnd, 0x3E8)
    if not arrange then return nil end
    ok, left, top, right, bottom = r.JS_Window_GetRect(arrange)
  elseif mode == "arrange_window" then
    if not r.JS_Window_FindChildByID or not r.JS_Window_GetRect then return nil end
    local arrange = r.JS_Window_FindChildByID(hwnd, 0x3E8)
    if not arrange then return nil end
    local arrange_ok, arrange_left, arrange_top, arrange_right = r.JS_Window_GetRect(arrange)
    local reaper_ok, _, _, reaper_right, reaper_bottom
    if r.JS_Window_GetClientRect then reaper_ok, _, _, reaper_right, reaper_bottom = r.JS_Window_GetClientRect(hwnd) end
    if not reaper_ok and r.JS_Window_GetRect then reaper_ok, _, _, reaper_right, reaper_bottom = r.JS_Window_GetRect(hwnd) end
    if not arrange_ok or not reaper_ok then return nil end
    ok = true
    left = arrange_left
    top = arrange_top
    right = reaper_right or arrange_right
    bottom = reaper_bottom
  elseif mode == "reaper" then
    if r.JS_Window_GetClientRect then ok, left, top, right, bottom = r.JS_Window_GetClientRect(hwnd) end
    if not ok and r.JS_Window_GetRect then ok, left, top, right, bottom = r.JS_Window_GetRect(hwnd) end
  else
    return nil
  end
  if not ok then return nil end
  left = tonumber(left)
  top = tonumber(top)
  right = tonumber(right)
  bottom = tonumber(bottom)
  if not left or not top or not right or not bottom then return nil end
  return left, top, right, bottom
end

local function auto_collapse_height_bounds()
  local mode = auto_collapse_height_mode()
  if mode == "manual" then return nil end
  local left, top, right, bottom = auto_collapse_target_rect(mode)
  if not left then return nil end
  if r.ImGui_PointConvertNative then
    local _, converted_top = r.ImGui_PointConvertNative(ctx, left, top)
    local _, converted_bottom = r.ImGui_PointConvertNative(ctx, right, bottom)
    top = tonumber(converted_top) or top
    bottom = tonumber(converted_bottom) or bottom
  end
  if bottom <= top then return nil end
  return top, bottom - top
end

local function auto_collapse_available()
  return app.settings.auto_collapse == true and app.cache.window_docked == false
end

local function auto_collapse_reaper_edge(side)
  if not r.GetMainHwnd then return nil end
  local hwnd = r.GetMainHwnd()
  if not hwnd then return nil end
  local ok, left, _, right
  if r.JS_Window_GetClientRect then ok, left, _, right = r.JS_Window_GetClientRect(hwnd) end
  if not ok and r.JS_Window_GetRect then ok, left, _, right = r.JS_Window_GetRect(hwnd) end
  if not ok then return nil end
  left = tonumber(left)
  right = tonumber(right)
  if not left or not right then return nil end
  if side == "right" then return right end
  return left
end

local function auto_collapse_native_edge(side)
  local reaper_edge = auto_collapse_reaper_edge(side)
  if reaper_edge then return reaper_edge end
  if not r.ImGui_GetMainViewport or not r.ImGui_Viewport_GetWorkPos or not r.ImGui_Viewport_GetWorkSize then return nil end
  local viewport = r.ImGui_GetMainViewport(ctx)
  if not viewport then return nil end
  local work_x = r.ImGui_Viewport_GetWorkPos(viewport)
  local work_w = r.ImGui_Viewport_GetWorkSize(viewport)
  work_x = tonumber(work_x)
  work_w = tonumber(work_w)
  if not work_x or not work_w then return nil end
  if side == "right" then return work_x + work_w end
  return work_x
end

local function auto_collapse_viewport_edge(side)
  local reaper_edge = auto_collapse_reaper_edge(side)
  if reaper_edge then
    if r.ImGui_PointConvertNative then
      local converted = r.ImGui_PointConvertNative(ctx, reaper_edge, 0)
      converted = tonumber(converted)
      if converted then return converted end
    end
    return reaper_edge
  end
  if not r.ImGui_GetMainViewport or not r.ImGui_Viewport_GetWorkPos or not r.ImGui_Viewport_GetWorkSize then return nil end
  local viewport = r.ImGui_GetMainViewport(ctx)
  if not viewport then return nil end
  local work_x = r.ImGui_Viewport_GetWorkPos(viewport)
  local work_w = r.ImGui_Viewport_GetWorkSize(viewport)
  work_x = tonumber(work_x)
  work_w = tonumber(work_w)
  if not work_x or not work_w then return nil end
  if side == "right" then return work_x + work_w end
  return work_x
end

local function auto_collapse_mouse_on_outer_edge()
  if not r.GetMousePosition then return false end
  local side = auto_collapse_side()
  local edge = auto_collapse_native_edge(side)
  if not edge then return false end
  local mouse_x = r.GetMousePosition()
  mouse_x = tonumber(mouse_x)
  if not mouse_x then return false end
  if not app.cache.auto_collapse_collapsed then
    if side == "right" then return mouse_x >= edge end
    return mouse_x <= edge
  end
  local margin = auto_collapse_edge_hover_margin()
  if side == "right" then return mouse_x >= edge and mouse_x <= edge + margin end
  return mouse_x <= edge and mouse_x >= edge - margin
end

local function auto_collapse_keep_open()
  if app.settings.auto_collapse_keep_expanded == true then return true end
  if auto_collapse_mouse_on_outer_edge() then return true end
  if app.cache.preferences_open or app.settings_panel then return true end
  if r.ImGui_IsPopupOpen and r.ImGui_PopupFlags_AnyPopupId then
    local ok, any_popup = pcall(r.ImGui_IsPopupOpen, ctx, "", r.ImGui_PopupFlags_AnyPopupId())
    if ok and any_popup then return true end
  end
  if r.ImGui_IsWindowHovered and r.ImGui_HoveredFlags_AnyWindow then
    local flags = r.ImGui_HoveredFlags_AnyWindow()
    if r.ImGui_HoveredFlags_AllowWhenBlockedByActiveItem then flags = flags | r.ImGui_HoveredFlags_AllowWhenBlockedByActiveItem() end
    if r.ImGui_IsWindowHovered(ctx, flags) then return true end
  end
  for _, module in ipairs(app.modules or {}) do
    if module.keep_workbench_expanded then
      local ok, keep = pcall(module.keep_workbench_expanded, app)
      if ok and keep then return true end
    end
  end
  if r.ImGui_IsAnyItemActive and r.ImGui_IsAnyItemActive(ctx) then return true end
  return false
end

local function apply_auto_collapse_window()
  local available = auto_collapse_available()
  if not available then
    app.cache.auto_collapse_collapsed = false
    app.cache.auto_collapse_force_restore = nil
    return
  end
  local collapsed = app.cache.auto_collapse_collapsed == true
  local force_restore = app.cache.auto_collapse_force_restore == true
  local min_w, min_h = expanded_window_min_size()
  local expanded_w = math.max(min_w, app.cache.auto_collapse_expanded_w or app.cache.window_w or app.settings.window_width or 430)
  local expanded_h = math.max(min_h, app.cache.auto_collapse_expanded_h or app.cache.window_h or app.settings.window_height or 760)
  local auto_top, auto_h = auto_collapse_height_bounds()
  if auto_h then expanded_h = math.max(min_h, auto_h) end
  local target_w = collapsed and auto_collapse_width() or expanded_w
  local target_h = expanded_h
  local cond_always = r.ImGui_Cond_Always and r.ImGui_Cond_Always() or 0
  if r.ImGui_SetNextWindowSizeConstraints then
    if collapsed then
      r.ImGui_SetNextWindowSizeConstraints(ctx, target_w, target_h, target_w, target_h)
    else
      r.ImGui_SetNextWindowSizeConstraints(ctx, min_w, min_h, 100000, 100000)
    end
  end
  if (collapsed or force_restore or auto_h) and r.ImGui_SetNextWindowSize then r.ImGui_SetNextWindowSize(ctx, target_w, target_h, cond_always) end
  if r.ImGui_SetNextWindowPos then
    local side = auto_collapse_side()
    local edge = auto_collapse_viewport_edge(side)
    if not edge and side == "right" and app.cache.window_x and app.cache.window_w then edge = app.cache.window_x + app.cache.window_w end
    if not edge and side == "left" and app.cache.window_x then edge = app.cache.window_x end
    if edge then
      local offset = collapsed and 0 or auto_collapse_edge_offset()
      local target_x = side == "right" and (edge - target_w - offset) or (edge + offset)
      r.ImGui_SetNextWindowPos(ctx, target_x, auto_top or app.cache.window_y or 0, cond_always)
    end
  end
  if force_restore and not collapsed then app.cache.auto_collapse_force_restore = nil end
end

local function save_expanded_window_size(docked)
  if docked or app.cache.auto_collapse_collapsed then return end
  local min_w, min_h = expanded_window_min_size()
  local width = math.floor(math.max(min_w, app.cache.window_w or app.settings.window_width or 430) + 0.5)
  local height = math.floor(math.max(min_h, app.cache.window_h or app.settings.window_height or 760) + 0.5)
  if math.abs(width - (tonumber(app.settings.window_width) or 0)) < 2 and math.abs(height - (tonumber(app.settings.window_height) or 0)) < 2 then return end
  app.settings.window_width = width
  app.settings.window_height = height
  local now = current_time()
  if now - (app.cache.window_size_last_save or 0) >= 0.75 then
    app.cache.window_size_last_save = now
    save_settings()
  else
    app.cache.window_size_dirty = true
  end
end

local function flush_window_size_if_dirty()
  if app.cache.window_size_dirty then
    app.cache.window_size_dirty = nil
    app.cache.window_size_last_save = current_time()
    save_settings()
  end
end

local function draw_auto_collapse_strip()
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetWindowPos(ctx)
  local w, h = r.ImGui_GetWindowSize(ctx)
  local side = auto_collapse_side()
  local border_x = side == "right" and x or (x + w)
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  r.ImGui_InvisibleButton(ctx, "##auto_collapse_handle", math.max(1, w), math.max(1, h))
  local hovered = r.ImGui_IsItemHovered(ctx)
  if hovered then
    r.ImGui_DrawList_AddLine(draw_list, border_x, y, border_x, y + h, Theme.colors.accent, 1)
    r.ImGui_SetTooltip(ctx, "Expand Workbench")
  end
end

local function push_auto_collapse_style()
  local vars = 0
  local colors = 0
  if app.cache.auto_collapse_collapsed and r.ImGui_StyleVar_WindowMinSize then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowMinSize(), 1, 1)
    vars = vars + 1
  end
  if app.cache.auto_collapse_collapsed and r.ImGui_StyleVar_WindowPadding then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, 0)
    vars = vars + 1
  end
  if app.cache.auto_collapse_collapsed and r.ImGui_StyleVar_WindowBorderSize then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowBorderSize(), 0)
    vars = vars + 1
  end
  if app.cache.auto_collapse_collapsed and r.ImGui_PushStyleColor and r.ImGui_Col_WindowBg then
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), 0x00000000)
    colors = colors + 1
  end
  if app.cache.auto_collapse_collapsed and r.ImGui_PushStyleColor and r.ImGui_Col_Border then
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), 0x00000000)
    colors = colors + 1
  end
  return vars, colors
end

local function pop_auto_collapse_style(vars, colors)
  if colors and colors > 0 then r.ImGui_PopStyleColor(ctx, colors) end
  if vars and vars > 0 then r.ImGui_PopStyleVar(ctx, vars) end
end

local function update_auto_collapse_state(window_hovered, docked)
  app.cache.window_docked = docked == true
  if app.settings.auto_collapse ~= true or docked then
    app.cache.auto_collapse_collapsed = false
    app.cache.auto_collapse_force_restore = nil
    app.cache.auto_collapse_last_hover_time = current_time()
    return
  end
  local now = current_time()
  local keep_open = window_hovered or auto_collapse_keep_open()
  if keep_open then
    app.cache.auto_collapse_last_hover_time = now
    if app.cache.auto_collapse_collapsed then
      app.cache.auto_collapse_collapsed = false
      app.cache.auto_collapse_force_restore = true
    end
    return
  end
  local last_hover = app.cache.auto_collapse_last_hover_time or now
  app.cache.auto_collapse_last_hover_time = last_hover
  if not app.cache.auto_collapse_collapsed and now - last_hover >= auto_collapse_delay() then
    local min_w, min_h = expanded_window_min_size()
    app.cache.auto_collapse_expanded_w = math.max(min_w, app.cache.window_w or app.settings.window_width or 430)
    app.cache.auto_collapse_expanded_h = math.max(min_h, app.cache.window_h or app.settings.window_height or 760)
    app.cache.auto_collapse_collapsed = true
  end
end

local function workbench_window_hovered()
  if not r.ImGui_IsWindowHovered then return false end
  local flags = 0
  if r.ImGui_HoveredFlags_RootAndChildWindows then flags = flags | r.ImGui_HoveredFlags_RootAndChildWindows() end
  if r.ImGui_HoveredFlags_AllowWhenBlockedByActiveItem then flags = flags | r.ImGui_HoveredFlags_AllowWhenBlockedByActiveItem() end
  return r.ImGui_IsWindowHovered(ctx, flags)
end

local function push_workspace_style()
  local vars = 0
  if app.settings.hide_scrollbars and r.ImGui_StyleVar_ScrollbarSize then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ScrollbarSize(), 0)
    vars = vars + 1
  end
  return vars
end

local function pop_workspace_style(vars)
  if vars and vars > 0 then r.ImGui_PopStyleVar(ctx, vars) end
end

local function draw_module_error(module, err)
  local width = r.ImGui_GetContentRegionAvail(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local pad = UIScale.round(10)
  local height = math.max(UIScale.round(72), math.ceil(r.ImGui_GetTextLineHeight(ctx) * 4.2))
  local bg = Theme.colors.frame_bg
  local warning_text = Theme.text_for_background(bg, Theme.colors.warning, nil, 4.5)
  local detail_text = Theme.text_for_background(bg, Theme.colors.text_dim, Theme.colors.text, 4.5)
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, bg, UIScale.px(5))
  r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + height, Theme.colors.warning, UIScale.px(5), 0, UIScale.px(1))
  r.ImGui_SetCursorScreenPos(ctx, x + pad, y + UIScale.round(8))
  r.ImGui_TextColored(ctx, warning_text, tostring(module and (module.title or module.id) or "Module") .. " error")
  r.ImGui_SetCursorScreenPos(ctx, x + pad, y + UIScale.round(30))
  r.ImGui_PushTextWrapPos(ctx, x + width - pad)
  r.ImGui_TextColored(ctx, detail_text, tostring(err))
  r.ImGui_PopTextWrapPos(ctx)
  r.ImGui_SetCursorScreenPos(ctx, x, y + height + UIScale.round(6))
  r.ImGui_Dummy(ctx, 1, 1)
end

local function draw_module_instance(module, pane_id)
  if not module then
    r.ImGui_TextColored(ctx, Theme.text_for_backgrounds({ Theme.colors.window_bg, Theme.colors.child_bg }, Theme.colors.warning, nil, 4.5), "No modules loaded")
    return
  end
  r.ImGui_PushID(ctx, pane_id or module.id)
  if module.draw then
    local ok, err = pcall(module.draw, app)
    if ok then
      clear_module_error(module.id .. ".draw")
    else
      record_module_error(module.id .. ".draw", err)
      draw_module_error(module, err)
    end
  end
  r.ImGui_PopID(ctx)
end

local function draw_splitter(total, orientation)
  local horizontal = orientation == "horizontal"
  local avail_w, avail_h = r.ImGui_GetContentRegionAvail(ctx)
  local thickness = UIScale.round(8)
  local width = horizontal and thickness or avail_w
  local height = horizontal and avail_h or thickness
  r.ImGui_InvisibleButton(ctx, "##workbench_splitter", width, height)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local active = r.ImGui_IsItemActive(ctx)
  if active and r.ImGui_GetMouseDragDelta then
    local drag_x, drag_y = r.ImGui_GetMouseDragDelta(ctx, 0, 0)
    local delta = horizontal and (drag_x or 0) or (drag_y or 0)
    if math.abs(delta) > 0 then
      app.settings.split_ratio = clamp((tonumber(app.settings.split_ratio) or 0.5) + delta / math.max(1, total), 0.18, 0.82)
      app.cache.split_ratio_dirty = true
      if r.ImGui_ResetMouseDragDelta then r.ImGui_ResetMouseDragDelta(ctx, 0) end
    end
  elseif app.cache.split_ratio_dirty then
    app.cache.split_ratio_dirty = nil
    save_settings()
  end
  local x1, y1 = r.ImGui_GetItemRectMin(ctx)
  local x2, y2 = r.ImGui_GetItemRectMax(ctx)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local background = Theme.colors.child_bg or Theme.colors.window_bg or 0x181818FF
  local rail_color = contrast_from_background(background, hovered and 0.16 or 0.11)
  local grip_color = active and Theme.colors.accent or contrast_from_background(background, hovered and 0.34 or 0.24)
  if horizontal then
    r.ImGui_DrawList_AddRectFilled(draw_list, x1 + 1, y1, x2 - 1, y2, rail_color, 3)
    r.ImGui_DrawList_AddRectFilled(draw_list, x1 + 3, y1 + 8, x2 - 3, y2 - 8, grip_color, 2)
  else
    r.ImGui_DrawList_AddRectFilled(draw_list, x1, y1 + 1, x2, y2 - 1, rail_color, 3)
    r.ImGui_DrawList_AddRectFilled(draw_list, x1 + 8, y1 + 3, x2 - 8, y2 - 3, grip_color, 2)
  end
  if hovered or active then r.ImGui_SetTooltip(ctx, "Drag to resize split") end
end

local function draw_module_canvas()
  if is_home_active() then
    draw_home_view()
    return
  end
  local module = get_active_module()
  if not split_view_available() then
    draw_module_instance(module, "primary")
    return
  end
  local split_module = get_split_module()
  local available_w, available_h = r.ImGui_GetContentRegionAvail(ctx)
  local horizontal = split_orientation() == "horizontal"
  local splitter_size = UIScale.round(8)
  local pane_flags = 0
  if r.ImGui_WindowFlags_NoScrollbar then pane_flags = pane_flags | r.ImGui_WindowFlags_NoScrollbar() end
  if r.ImGui_WindowFlags_NoScrollWithMouse then pane_flags = pane_flags | r.ImGui_WindowFlags_NoScrollWithMouse() end
  local ratio = clamp(tonumber(app.settings.split_ratio) or 0.5, 0.18, 0.82)
  if horizontal then
    local total_w = math.max(40, available_w or 240)
    local spacing_x = 7
    if r.ImGui_GetStyleVar and r.ImGui_StyleVar_ItemSpacing then
      local sx = r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing())
      spacing_x = tonumber(sx) or spacing_x
    end
    local content_w = math.max(20, total_w - splitter_size - spacing_x * 2)
    local min_w = math.min(UIScale.round(220), math.floor(content_w * 0.45))
    local left_w = clamp(math.floor(content_w * ratio), min_w, math.max(min_w, content_w - min_w))
    local right_w = math.max(20, content_w - left_w)
    local left_visible = r.ImGui_BeginChild(ctx, "##workbench_split_primary", left_w, 0, 0, pane_flags)
    if left_visible then draw_module_instance(module, "primary") end
    r.ImGui_EndChild(ctx)
    r.ImGui_SameLine(ctx, 0, 0)
    draw_splitter(content_w, "horizontal")
    r.ImGui_SameLine(ctx, 0, 0)
    local right_visible = r.ImGui_BeginChild(ctx, "##workbench_split_secondary", right_w, 0, 0, pane_flags)
    if right_visible then draw_module_instance(split_module, "secondary") end
    r.ImGui_EndChild(ctx)
    return
  end
  local total_h = math.max(40, available_h or 240)
  local spacing_y = 7
  if r.ImGui_GetStyleVar and r.ImGui_StyleVar_ItemSpacing then
    local _, current_spacing_y = r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing())
    spacing_y = tonumber(current_spacing_y) or spacing_y
  end
  local content_h = math.max(20, total_h - splitter_size - spacing_y * 2)
  local min_h = math.min(100, math.floor(content_h * 0.45))
  local top_h = math.floor(content_h * ratio)
  top_h = clamp(top_h, min_h, math.max(min_h, content_h - min_h))
  local bottom_h = math.max(20, content_h - top_h)
  local primary_visible = r.ImGui_BeginChild(ctx, "##workbench_split_primary", 0, top_h, 0, pane_flags)
  if primary_visible then draw_module_instance(module, "primary") end
  r.ImGui_EndChild(ctx)
  draw_splitter(content_h, "vertical")
  local secondary_visible = r.ImGui_BeginChild(ctx, "##workbench_split_secondary", 0, bottom_h, 0, pane_flags)
  if secondary_visible then draw_module_instance(split_module, "secondary") end
  r.ImGui_EndChild(ctx)
end

local function visible_module_error_ids()
  local result = {}
  if is_home_active() then return result end
  local active = get_active_module()
  if active then result[active.id] = true end
  if split_view_available() then
    local split_module = get_split_module()
    if split_module then result[split_module.id] = true end
  end
  return result
end

local function module_error_status()
  local visible = visible_module_error_ids()
  for key, err in pairs(app.module_errors) do
    local module_id, phase = tostring(key):match("^(.-)%.(.+)$")
    module_id = module_id or tostring(key)
    phase = phase or "module"
    if phase ~= "draw" or visible[module_id] then return key, err end
  end
  return nil
end

local function module_error_text(key)
  local module_id, phase = tostring(key):match("^(.-)%.(.+)$")
  module_id = module_id or tostring(key)
  phase = phase or "module"
  local module = app.modules_by_id[module_id]
  local title = tostring(module and (module.title or module.id) or module_id)
  return title .. " " .. phase .. " error"
end

local function draw_status_bar()
  local selection = app.selection or {}
  local captured = UI.get_captured_info_line(app)
  local text = captured and tostring(captured.text or "") or (app.status or "Ready")
  local captured_options = captured and captured.options or {}
  local details = ""
  local severity = captured_options.severity or "info"
  if captured_options.details then details = tostring(captured_options.details) end
  if selection.track and selection.track.name then text = text .. " | Track: " .. selection.track.name end
  if selection.item and selection.item.take_name then text = text .. " | Take: " .. selection.item.take_name end
  local key, err = module_error_status()
  if key then
    text = module_error_text(key)
    details = tostring(err) .. "\n\nLogged to workbench_errors.txt."
    severity = "error"
  end
  UI.draw_info_line(ctx, text, { severity = severity, details = details, force = true })
end

local function update_modules()
  for _, module in ipairs(app.modules) do
    if module.update then
      local ok, err = pcall(module.update, app)
      if ok then clear_module_error(module.id .. ".update") else record_module_error(module.id .. ".update", err) end
    end
  end
end

local function shutdown()
  if app.cache.shutdown_done then return end
  app.cache.shutdown_done = true
  r.SetExtState(MODULE_ACTION_EXT_SECTION, MODULE_ACTION_RUNNING_KEY, "false", false)
  r.SetExtState(MODULE_ACTION_EXT_SECTION, MODULE_ACTION_HEARTBEAT_KEY, "", false)
  for _, module in ipairs(app.modules) do
    if module.shutdown then pcall(module.shutdown, app) end
  end
  if app.settings.theme_preset == "Unsaved Custom" then
    app.settings.theme_preset = app.cache.saved_theme_preset or "Graphite"
  end
  save_settings()
end

if r.atexit then r.atexit(shutdown) end

local function draw_shell()
  draw_top_bar()
  local status_h = app.settings.show_status and UI.info_line_height(ctx, true) or 0
  local _, available_h = r.ImGui_GetContentRegionAvail(ctx)
  local canvas_h = math.max(40, (available_h or 240) - status_h)
  local canvas_flags = 0
  if r.ImGui_WindowFlags_NoScrollbar then canvas_flags = canvas_flags | r.ImGui_WindowFlags_NoScrollbar() end
  if r.ImGui_WindowFlags_NoScrollWithMouse then canvas_flags = canvas_flags | r.ImGui_WindowFlags_NoScrollWithMouse() end
  app.cache.captured_info_line = nil
  local child_visible = r.ImGui_BeginChild(ctx, "##workbench_module_canvas", 0, canvas_h, 0, canvas_flags)
  if child_visible then
    UI.begin_info_line_capture(app)
    draw_module_canvas()
    UI.end_info_line_capture(app)
    r.ImGui_Dummy(ctx, 1, 1)
  end
  r.ImGui_EndChild(ctx)
  if app.settings.show_status then draw_status_bar() end
end

local function loop()
  if r.ImGui_ValidatePtr and not r.ImGui_ValidatePtr(ctx, "ImGui_Context*") then
    ctx = r.ImGui_CreateContext(SCRIPT_NAME)
    app.ctx = ctx
    app.cache.tooltip = nil
    app.cache.ui_fonts = {}
    app.cache.ui_font_ctx = nil
  end
  set_ui_scale(app.settings.ui_scale or 1.0)
  app.selection = Selection.scan()
  update_modules()
  r.SetExtState(MODULE_ACTION_EXT_SECTION, MODULE_ACTION_RUNNING_KEY, "true", false)
  r.SetExtState(MODULE_ACTION_EXT_SECTION, MODULE_ACTION_HEARTBEAT_KEY, tostring(r.time_precise and r.time_precise() or os.clock()), false)
  process_module_action_commands()
  UI.begin_tooltip_frame(app)
  r.ImGui_SetNextWindowSize(ctx, app.settings.window_width or 430, app.settings.window_height or 760, r.ImGui_Cond_FirstUseEver())
  apply_auto_collapse_window()
  if (app.settings.theme_preset or "Graphite") ~= Theme.current_preset then
    app.settings.theme_preset = Theme.set_preset(app.settings.theme_preset or "Graphite", app.settings.custom_themes)
  end
  local scaled_font_pushed = push_scaled_font()
  local theme_stack = Theme.push(ctx, app.settings.child_bg_alpha or 1.0)
  local workspace_style_vars = push_workspace_style()
  local auto_collapse_style_vars, auto_collapse_style_colors = push_auto_collapse_style()
  local window_flags = r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
  if app.settings.auto_collapse == true and app.cache.window_docked == false and r.ImGui_WindowFlags_NoMove then
    window_flags = window_flags | r.ImGui_WindowFlags_NoMove()
  end
  if r.ImGui_SetNextWindowBgAlpha then
    r.ImGui_SetNextWindowBgAlpha(ctx, app.settings.window_bg_alpha or 1.0)
  end
  local visible, open = r.ImGui_Begin(ctx, SCRIPT_NAME, true, window_flags)
  if visible then
    app.cache.window_x, app.cache.window_y = r.ImGui_GetWindowPos(ctx)
    app.cache.window_w, app.cache.window_h = r.ImGui_GetWindowSize(ctx)
    local docked = r.ImGui_IsWindowDocked and r.ImGui_IsWindowDocked(ctx) or false
    if app.cache.auto_collapse_collapsed and not docked then
      draw_auto_collapse_strip()
    else
      if app.settings.auto_collapse == true and not docked then
        local min_w, min_h = expanded_window_min_size()
        app.cache.auto_collapse_expanded_w = math.max(min_w, app.cache.window_w or app.settings.window_width or 430)
        app.cache.auto_collapse_expanded_h = math.max(min_h, app.cache.window_h or app.settings.window_height or 760)
      end
      draw_shell()
    end
    save_expanded_window_size(docked)
    update_auto_collapse_state(workbench_window_hovered(), docked)
    r.ImGui_End(ctx)
  end
  draw_preferences_settings()
  UI.end_tooltip_frame(app)
  pop_auto_collapse_style(auto_collapse_style_vars, auto_collapse_style_colors)
  pop_workspace_style(workspace_style_vars)
  Theme.pop(ctx, theme_stack)
  pop_scaled_font(scaled_font_pushed)
  flush_window_size_if_dirty()
  if open and not app.close_requested then
    r.defer(loop)
  else
    shutdown()
  end
end

ModuleLoader.load(app, module_names)
apply_module_order()
if app.settings.active_module ~= HOME_MODULE_ID and not app.modules_by_id[app.settings.active_module] and app.modules[1] then
  app.settings.active_module = app.modules[1].id
  save_settings()
end

r.defer(loop)