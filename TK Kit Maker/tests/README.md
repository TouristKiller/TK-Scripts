# Tests

```bash
python tests/run_all.py
```

Prints a summary and exits non-zero if anything fails.

**REAPER is not involved.** Each suite stubs the handful of REAPER functions it
needs, so this runs with REAPER closed and never reads or writes your samples.
The one exception is `test_stale.lua`, which writes a few dummy files to a
folder under `%TEMP%`.

## Setup, once

Python plus [lupa](https://pypi.org/project/lupa/), which supplies the Lua
interpreter:

```bash
pip install lupa
```

## What runs

| | |
|---|---|
| `syntax_check.py` | Compiles every `.lua` in the project. |
| `forward_refs.py` | Finds calls to a `local function` defined further down. |
| `test_analyzer.lua` | The DSP, against synthetic one-shots: attack, decay, spectrum, tonality, stereo width. |
| `test_naming.lua` | Note names and export filenames. |
| `test_tagfilter.lua` | Tag filtering and the faceted counts; the SOURCE keyword rules. |
| `test_uidata.lua` | What the tags panel reads; the tone axis spread and the tonality boundaries. |
| `test_heatmap.lua` | Grid placement, the cell walk, cell↔pad mapping, projecting a kit. |
| `test_charbias.lua` | Character bias: that it weights and never excludes, and the focus curve. |
| `test_patternslots.lua` | "From pattern": parsing, and matching a word to a pool alias. |
| `test_pools.lua` | Pool id allocation after loading a preset. |
| `test_fixedpool.lua` | A heatmap-cell pool keeping its files through a scan and a preset round-trip. |
| `test_channels.lua` | The MONO/STEREO filter axis reaching the filter, the counts and the popup. |
| `test_seed.lua` | Seeded generation: reproducibility, the frozen sequence, and that neighbouring seeds are unrelated. |
| `test_groovescan.lua` | Finding groove files: subfolders and their names, depth, built-ins, and that the extension is kept rather than assumed. |
| `test_groove.lua` | Reading a groove out of a real MIDI file: swing, pushes, running status, refusals. |
| `test_gmemmap.lua` | That the shared-memory map in sequencer_view.lua and the JSFX engine still agree. |
| `test_groovesched.lua` | A model of the engine's groove scheduling, against block boundaries and buffer sizes. |
| `test_slice.lua` | Slicing a loop across pads: seams, bar counts, truncation and the nudge limits. |
| `test_rs5kparams.lua` | Finding RS5K parameters by name against its real list, including the two that collide. |
| `test_undo.lua` | The Builder undo: snapshots that do not share tables, and restores that keep references. |
| `test_wavcues.lua` | Reading cue points out of a WAV, and slicing on them instead of evenly. |
| `test_sliceexport.lua` | Writing a trimmed pad out as its own WAV: frame alignment, headers kept, and what it refuses. |
| `test_sortlist.lua` | Ordering the sample list: numbered names, unmeasured lengths, a stable order, and that the scan order survives. |
| `test_colgroups.lua` | Grouping collections: one heading however it is spelled, pinned staying on top, and Move Up acting on what is on screen. |
| `test_peaks.lua` | Transient detection: hits found once each, level independence, and that a steady tone is not sliced. |
| `test_stale.lua` | Detecting an edited sample, and that a cache without the stamp still loads. |

## Why these two extra checks

A Lua syntax error only surfaces when the offending screen is drawn, which in a
UI script can be days later.

The forward-reference check exists because Lua resolves a `local function` used
above its definition as a **global** — nil at run time, "attempt to call a nil
value", and the file compiles cleanly. It has caught that here more than once.

## Writing another

Copy the shape of an existing one:

```lua
local KIT = assert(TEST_DIR, "run these through tests/run_all.py") .. "/../"
package.path = KIT .. "?.lua;" .. package.path
reaper = { --[[ only what the code under test calls ]] }

local fail = 0
local function check(label, ok, got)
  if not ok then fail = fail + 1 print("FAIL: " .. label .. "  (got " .. tostring(got) .. ")") end
end

-- ... checks ...

print(fail == 0 and "ALL CHECKS PASSED" or (fail .. " CHECK(S) FAILED"))
TEST_FAILED = fail   -- the runner reads this; printing alone is not enough
```

`TEST_DIR` is set by the runner, so nothing has a path baked into it.

To stub the analyser rather than feed it audio, replace the one function:

```lua
local Analyzer = require("core.analyzer")
Analyzer.analyze = function(path) return my_metrics[path] end
local Tags = require("core.tags")   -- picks up the replacement
```

## Worth knowing

Say what the failure would cost, not what the code does — a check named
*"a kit stuck in one corner projects into one cell"* explains itself when it
goes red two years from now; *"test project 3"* does not.
