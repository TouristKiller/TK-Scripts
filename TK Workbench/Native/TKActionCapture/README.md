# TK Action Capture

Native REAPER extension for TK Workbench Action Clipboard auto capture.

The extension registers REAPER post-command hooks and writes captured action events to ExtState section `TK_WORKBENCH_ACTION_CAPTURE`. TK Workbench reads those events from Lua and records them in Action Clipboard history and slots.

## Build outputs

- Windows: `bin/windows-x64/reaper_tk_action_capture.dll`
- macOS: `bin/macos-universal/reaper_tk_action_capture.dylib`
- Linux: `bin/linux-x64/reaper_tk_action_capture.so`

## Local build

Requirements:

- CMake 3.21 or newer
- A native C++ toolchain for the target OS
- Git access to `https://github.com/justinfrankel/reaper-sdk.git`, unless `REAPER_SDK_DIR` is set manually

Windows:

```powershell
cmake --preset windows-msvc-x64
cmake --build --preset windows-msvc-x64-release
```

macOS:

```sh
cmake --preset macos-universal
cmake --build --preset macos-universal-release
```

Linux:

```sh
cmake --preset linux-x64
cmake --build --preset linux-x64-release
```

Copy the built extension from the preset `build/*/bin` folder to the REAPER `UserPlugins` folder and restart REAPER.

## CI build

The repository workflow builds Windows, macOS and Linux artifacts with GitHub Actions. Store downloaded artifacts in the matching `bin/<platform>` folder for ReaPack delivery. ReaPack installs the native binaries into the Workbench folder; copy the extension for the target platform manually into the REAPER `UserPlugins` folder.

## ExtState

Section: `TK_WORKBENCH_ACTION_CAPTURE`

Keys:

- `available`: `true` while the extension is loaded
- `seq`: latest sequence number
- `events`: newline-separated queue of `seq|time|section|command|source`

Only command IDs are captured. Scripts that directly mutate the project through ReaScript API calls without executing REAPER actions will not produce events.