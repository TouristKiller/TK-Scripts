# TK Theme Dark (beta)

A dark theme for REAPER 7, built on Default 7.0. Glass windows in the style of an
LCD display, flat icons, and one accent colour per function. It comes with its
own settings window, so you can change it without editing anything by hand.

## Install

You need [ReaPack](https://reapack.com) and, for the settings window, ReaImGui
0.10 or newer (ReaPack: ReaTeam Extensions).

1. In ReaPack, import this repository:
   `https://github.com/TouristKiller/TK-Scripts/raw/master/index.xml`
2. Install **TK Theme Dark** (category TK Theme).
3. Options > Themes > **TK Theme Dark**.
4. Click the gear at the end of the transport to open the settings.
5. Click the columns button in a track panel to show the FX and IO columns. That also
   turns on REAPER's options to show FX and sends in the track panel.

On Windows, the settings window offers to apply matching colours to REAPER's
lists, menus and borders. That takes effect after a restart.

## What's in it

- **Transport:** up to two windows of extra buttons, left and right of the
  transport. Each button can run an action of your choice. When the transport
  gets too narrow, they move to a second row.
- **Metronome button** that lights up while the metronome is on. Click its small
  arrow for the metronome settings. "Metronome light at startup" also keeps it
  right before your first click; it adds one line to `Scripts/__startup.lua`,
  and switching it off removes that line again.
- **Track panel:** FX and send columns, FX parameters under the controls, buttons for
  fixed lanes and freeze. The master has the same windows, with its hardware outputs
  in the IO column.
- **Mixer:** a fader cap or a dot, and three layouts.
- **Envelope lanes, media items, MIDI editor, inline MIDI editor:** all redrawn.
- **Settings:** every option on one page per area, a colour editor, a factory reset
  that you can undo, and a Guide page that explains the theme.

## Windows only

- **Dark mode colours** are written to `win32_darkmode_colors` in `reaper.ini`.
  The page keeps your own colours, and can go back to REAPER's original ones.
- **Hiding the menu bar** needs TK Native Helper 1.1.0 or newer (also in this
  repository). Its action is `TK_Theme_Toggle_Menu_Bar`, for a shortcut.

Popup menus, buttons and dropdowns in REAPER's windows keep their own grey: none of
REAPER's colour settings changes them.

## Toolbar icons

ReaPack also installs a set of `TK_` icons for your own toolbars. Right-click a
toolbar > Customize toolbar, select a button, click Icon, and choose a `TK_` icon.
A button that toggles has an `_off` and an `_on` file: choose `_off`.

## Good to know

- This is a beta. It has been tested on Windows at 100%, 150% and 200%. Mac and
  Linux have not been confirmed yet; reports are welcome.
- Colours you save go into `ColorThemes/TK Theme Dark.ReaperTheme`. Updating the
  theme with ReaPack replaces that file, so changed colours have to be set again.
- Transport buttons call scripts through action IDs that depend on the install
  path. Leave the files where ReaPack puts them.
