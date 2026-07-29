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
