# REAPER ReaScript (Lua) Development Instructions

This repository contains REAPER scripts written in Lua, often utilizing the SWS Extension and ReaImGui.

## General Guidelines
- **Language:** Always answer in **Dutch** (Nederlands).
- **Comments:** Be very sparing with comments. Only add them if absolutely necessary for structure or clarification. Avoid explaining obvious code.

## Core Dependencies & API
- **API Alias:** Always alias the `reaper` object to `r` at the start of the script (`local r = reaper`).
- **SWS Extension:** Assume SWS is available but check for it (e.g., `if not r.BR_GetMediaItemGUID then ...`). Use SWS functions for advanced item manipulation and GUID handling.
- **ReaImGui:** Use `reaper.ImGui` for graphical user interfaces. Create a context and use the `defer` loop pattern.

## Script Structure
1.  **Metadata Header:** Start with a standard ReaPack header:
    ```lua
    -- @description Script Name
    -- @author TouristKiller
    -- @version 1.0
    -- @changelog:
    --   + Initial release
    ```
2.  **Main Loop:** For GUI scripts, use a recursive `loop()` function called via `r.defer(loop)`.
3.  **Undo Management:** Wrap ALL project modifications in an Undo Block:
    ```lua
    r.Undo_BeginBlock()
    -- ... modifications ...
    r.Undo_EndBlock("Action Name", -1)
    ```
4.  **Prevent UI Refresh:** Use `r.PreventUIRefresh(1)` and `r.PreventUIRefresh(-1)` around heavy operations to improve performance and prevent flickering.

## Critical Patterns

### Media Item Handling
- **GUIDs vs Pointers:** When storing references to MediaItems across `defer` cycles or UI frames, ALWAYS store the **GUID** (`r.BR_GetMediaItemGUID`), not the pointer. Pointers are unstable and can change or become invalid.
- **Retrieval:** Retrieve the item pointer from the GUID immediately before use (`r.BR_GetMediaItemByGUID`).

### MIDI Processing
- **Time vs PPQ:** Be explicit about converting between Project Time and PPQ (Pulses Per Quarter note).
- **Pooled Copies:** When creating "ghost" copies, use `r.Main_OnCommand(41072, 0)` (Paste as pooled MIDI source).
- **Clean Sources:** When extracting a specific time selection to a new item, use **Glue** (`41588`) on the temp item to ensure the underlying MIDI source starts at offset 0.

### ReaImGui UI Patterns
- **BeginChild:** Never use boolean `true` or `false` as the border parameter for `r.ImGui_BeginChild`. Use `1` (border) or `0` (no border) or specific flags.
- **Theming:** Define a `COLORS` table with hex values (e.g., `0x7AA2F7FF`). Use a helper function `ApplyTheme()` to push style vars/colors and `PopTheme()` to pop them.
- **Fonts:** Load fonts once outside the loop (check `if not font_loaded`).
- **IDs:** Use `r.ImGui_PushID` inside loops to ensure unique widget IDs.

## Terminology
- **Phrase:** Prefer the term "Phrase" over "Segment" when referring to a musical pattern or sub-section of a MIDI item in the UI.
