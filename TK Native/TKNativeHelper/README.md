# TK Native Helper

Shared native REAPER extension for TK scripts. Provides an OS-level file drag-and-drop
so files from **TK Media Browser** and the **TK Workbench Media Browser** can be dragged
onto external plugin windows (for example Speedrum sample slots).

This extension is installed separately in the REAPER `UserPlugins` folder and works
independently of whichever TK scripts are installed. Scripts detect it at runtime and
only expose the drag-to-plugin feature when the extension is present.

## Exposed ReaScript API

- `reaper.TK_StartFileDrag(file_path)` -> `boolean`
  - Starts a native OS drag-and-drop for `file_path`.
  - Returns `true` when the file was dropped on a target.
  - Windows (OLE), macOS (NSDraggingSession) and Linux (XDND) are implemented.

Scripts guard the feature with `if reaper.TK_StartFileDrag then ... end`.

## Build outputs

- Windows: `reaper_tk_native_helper.dll`
- macOS: `reaper_tk_native_helper.dylib`
- Linux: `reaper_tk_native_helper.so`

## Local build (Windows)

Requirements:

- Visual Studio 2022 Build Tools with the C++ workload
- CMake 3.21 or newer
- Git access to `https://github.com/justinfrankel/reaper-sdk.git`, unless `REAPER_SDK_DIR` is set manually

From a Developer PowerShell:

```powershell
cd "$env:APPDATA\REAPER\Scripts\TK Scripts\TK Native\TKNativeHelper"
.\build_and_install.ps1
```

The script configures, builds and copies the DLL into `UserPlugins`. Restart REAPER afterwards.

## macOS / Linux

The native drag is implemented on all three platforms. The API is registered
everywhere; scripts keep using the same `if reaper.TK_StartFileDrag then ... end`
guard.

- macOS uses `NSDraggingSession` (Cocoa framework).
- Linux uses the XDND protocol over Xlib (`libX11`).

Both platforms initiate the drag from the current mouse position. Because macOS and
Linux require an active mouse button for a drag session, the drag should be triggered
while the mouse button is still held down.

```sh
cmake --preset macos-universal
cmake --build --preset macos-universal-release
```

```sh
cmake --preset linux-x64
cmake --build --preset linux-x64-release
```

Copy the resulting `reaper_tk_native_helper.dylib` / `.so` from the build `bin` folder
into `~/Library/Application Support/REAPER/UserPlugins` (macOS) or
`~/.config/REAPER/UserPlugins` (Linux) and restart REAPER.
