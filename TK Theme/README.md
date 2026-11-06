# TK Theme (beta)

A theme for REAPER 7, built on Default 7.0, with a Dark and a Light look. Glass windows
in the style of an LCD display, flat icons, and one accent colour per function. It comes
with its own settings window, so you can change it without editing anything by hand.

## Install

You need [ReaPack](https://reapack.com) and, for the settings window, ReaImGui
0.10 or newer (ReaPack: ReaTeam Extensions).

1. In ReaPack, import this repository:
   `https://github.com/TouristKiller/TK-Scripts/raw/master/index.xml`
2. Install **TK Theme** (category TK Theme).
3. Options > Themes > **TK Theme Dark** or **TK Theme Light**.
4. Click the gear at the end of the transport to open the settings.
5. Click the columns button in a track panel to show the FX and IO columns on that
   track's layout. That also turns on REAPER's options to show FX and sends in the track
   panel.

On Windows, the settings window offers to apply matching colours to REAPER's
lists, menus and borders. That takes effect after a restart.

## What's in it

- **Looks:** Dark and Light, chosen on the Look page of the settings. A look changes colours
  and images, and your layout settings go along. In Options > Themes they are two themes:
  choosing one there works too, but your settings only go along from the Look page.
- **Accent colours:** Blue, Orange and Violet, for selections, FX buttons, highlights, meters
  and the theme's icons.
- **Display:** Ice, Amber, Green, Red or Blue: dark glass on the transport with everything on it
  in one colour, in both looks. Standard follows the look and its accent colour.
- **Text buttons on toolbars:** plain, or with a quiet cell behind them, and small, normal or large text.
- **FX and send lists:** plain, or a subtle grid above the mixer's strips.
- **Transport plate:** Black or Silver: brushed metal behind the whole transport, with screws and
  a maker's plate, on the General page.
- **Colour settings:** Standard, Warm, Cool, Neutral and Inverted, for the arrange, grid, mixer
  background and lists. Inverted gives Dark a light arrange and Light a dark one.
- **Meters:** six types with colour steps, and segments in three sizes. The steps assume
  REAPER's standard meter range of -60 to +6 dB.
- **Transport:** up to two windows of extra buttons, left and right of the
  transport. Each button can run an action of your choice. When the transport
  gets too narrow, they move to a second row.
- **Metronome button** that lights up while the metronome is on. Click its small
  arrow for the metronome settings. "Metronome light at startup" also keeps it
  right before your first click; it adds one line to `Scripts/__startup.lua`,
  and switching it off removes that line again.
- **Track panel:** a choice of slider handles, sliders or knobs for volume and pan, which can
  also sit on the first row so they show on the lowest track height, FX and IO columns, FX parameters under the controls, buttons for
  fixed lanes and freeze, and a blue strip on tracks with fixed lanes. The master has the
  same windows, with its hardware outputs in the IO column, or can be one big meter.
- **Layouts:** A, B and C can each leave out or move parts of the track panel and mixer
  strip. Name only turns a track into a divider, and a track's height can be set and locked.
- **Mixer:** five fader handles to choose from by their picture, handles for pan and width, a sidebar with 1 to 4 columns, and settings for the
  normal, intermediate and narrow strip.
- **Envelope lanes, media items, MIDI editor, inline MIDI editor:** all redrawn.
- **Settings:** every option on one page per area, a colour editor with a reset per colour,
  kept per look, colour processing for the whole theme, presets that remember their look, a
  factory reset that you can undo, and a Guide page that explains the theme.

## Windows only

- **Dark mode colours** are written to `win32_darkmode_colors` in `reaper.ini`.
  The page keeps your own colours, and can go back to REAPER's original ones.
- **Hiding the menu bar** needs TK Native Helper 1.1.0 or newer (also in this
  repository). Its action is `TK_Theme_Toggle_Menu_Bar`, for a shortcut.

Popup menus, buttons and dropdowns in REAPER's windows keep their own grey: none of
REAPER's colour settings changes them.

## Toolbar icons

ReaPack also installs a set of `TK_` icons for your own toolbars, including `TK_MIDI_`
icons for the MIDI editor. Right-click a toolbar > Customize toolbar, select a button,
click Icon, and choose a `TK_` icon. A button that toggles has an `_off` and an `_on` file:
choose `_off`. The settings window puts the icons of the chosen look in `Data/toolbar_icons`,
over the earlier ones of this set. These `TK_` icons keep the look's blue under another accent
colour; the theme's own icons follow it.

## Good to know

- This is a beta. It has been tested on Windows at 100%, 150% and 200%, and a user
  reports it works on Mac so far. Linux hasn't been confirmed yet; reports are welcome.
- An update replaces the theme files in `ColorThemes`. Colours you saved and everything you
  chose come back by themselves the next time you open the settings; until then you see the
  theme's own. With Light chosen, the TK_ icons come back the same way.
- Transport buttons call scripts through action IDs that depend on the install
  path. Leave the files where ReaPack puts them.
