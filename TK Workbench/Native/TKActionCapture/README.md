# TK Action Capture

Native REAPER extension proof-of-concept for TK Workbench Action Clipboard auto capture.

This is the live local development copy. REAPER only loads the built extension from the REAPER `UserPlugins` folder; the C++ source in this folder is only needed while developing or rebuilding the native module.

The extension registers REAPER post-command hooks and writes captured action events to ExtState section `TK_WORKBENCH_ACTION_CAPTURE`. TK Workbench reads those events from Lua and records them into the Action Clipboard slots.

## Build outputs

- Windows: `reaper_tk_action_capture.dll`
- macOS: `reaper_tk_action_capture.dylib`
- Linux: `reaper_tk_action_capture.so`

## Local build

Requirements on Windows:

- Visual Studio 2022 Build Tools with C++ workload
- CMake 3.21 or newer
- Git access to `https://github.com/justinfrankel/reaper-sdk.git`, unless `REAPER_SDK_DIR` is set manually

From a Developer PowerShell:

```powershell
cd "$env:APPDATA\REAPER\Scripts\TK Scripts\TK Workbench\Native\TKActionCapture"
cmake --preset windows-msvc-x64
cmake --build --preset windows-msvc-x64-release
```

On macOS:

```sh
cmake --preset macos-universal
cmake --build --preset macos-universal-release
```

On Linux:

```sh
cmake --preset linux-x64
cmake --build --preset linux-x64-release
```

Or in VS Code, open this folder and run:

```text
Terminal: Run Build Task
```

Then choose:

```text
Build and install TK Action Capture
```

Install the built DLL:

```powershell
Copy-Item .\build\windows-msvc-x64\bin\reaper_tk_action_capture.dll "$env:APPDATA\REAPER\UserPlugins\reaper_tk_action_capture.dll" -Force
```

Restart REAPER after copying the extension.

## CI build

The repository workflow builds Windows, macOS and Linux artifacts with GitHub Actions. Download the artifact for the target platform and copy the extension manually into the REAPER `UserPlugins` folder.

## ExtState

Section: `TK_WORKBENCH_ACTION_CAPTURE`

Keys:

- `available`: `true` while the extension is loaded
- `seq`: latest sequence number
- `events`: newline-separated queue of `seq|time|section|command|source`

Only command IDs are captured. Scripts that directly mutate the project through ReaScript API calls without executing REAPER actions will not produce events.