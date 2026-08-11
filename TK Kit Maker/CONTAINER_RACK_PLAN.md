# Container racks — implementation plan

A rack as RS5K instances inside one FX container on a single track, beside the
existing one-track-per-pad rack. From AndreiMir's request: dozens of tracks per
kit is a project you cannot read.

Written after the spike (`TK_Probe_Container_Rack.lua`, run on REAPER 7.75).
Everything in "What the spike settled" is measured, not assumed.

## Where this is

| Phase | | |
|---|---|---|
| 1 | The Lane layer | done, smoke-tested |
| 2 | Rack identity | done |
| 3 | Building a container rack | done, smoke-tested: 16 pads play from a MIDI controller |
| 4 | The sequencer | done, smoke-tested: patterns play, per-pad parameters work, it exports |
| 5 | The Kit Manager | done, smoke-tested |
| 6 | Save kit | rides on 5 -- it is entirely row-based, and trimmed_range already took (track, fx) |
| 7 | The edges | done |

Nothing is committed. The whole feature lives in the REAPER Scripts working
copy; `TK Kit Maker copy` beside it is 0.2.50 as published, and is the way back.

All seven phases are built. A container rack can be created, sequenced on both
pages, exported, edited in the Kit Manager and saved out as a kit folder. It is
still labelled experimental because it has been in existence for one session.

---

## What the spike settled

**Placing an FX inside a container works directly.**

```lua
TrackFX_AddByName(track, "ReaSamplOmatic5000 (Cockos)", false, -1000 - addr)
```

No add-then-move dance. Confirmed on 7.75.

**Containers pass MIDI, and per-instance note ranges separate the pads.** Two
RS5Ks inside a container each answered their own note and stayed silent on the
others. An unmapped note came back 58 dB down — meter residue, not a trigger.

**RS5Ks in series sum rather than replace.** Pad 1's audio reached the meter
through two other RS5K instances. That is what makes many samplers on one track
work at all, and it now has evidence behind it rather than folklore.

**A container address is an expression, not an identity.**

```lua
addr = 0x2000000 + (container_index + 1) + (top_level_fx_count + 1) * child_index
```

The `top_level_fx_count` term means every child address moves when an FX is
added to or removed from the track. The probe itself was caught by this: it
computed two addresses, added one more FX, and then wrote to addresses that no
longer pointed anywhere — silently, with no error.

**This is the single most important constraint in the whole feature.** A lane
must resolve its address on use, every time. Cache it and the first user who
drops an EQ on the track silently repoints all sixteen pads.

## What is still assumed

Not yet seen, and to be watched for in Phase 3 rather than probed separately —
if any of it breaks, it breaks loudly and immediately:

- sixteen instances rather than two
- the sequencer's engine JSFX sitting above the container and feeding it
- the per-pad parameter setters (pitch, pan, volume, attack, release) through a
  container address; they use the same `TrackFX_*` calls, so the expectation is
  that nothing changes, but expecting is not seeing

---

## The shape of the problem

`lane_track` appears about 115 times in `ui/sequencer_view.lua`. Nearly every one
of them looks like this:

```lua
local lane_track = lane_tracks[lane]
local lane_fx = lane_track and find_rs5k_fx(lane_track) or -1
set_rs5k_volume_db(lane_track, lane_fx, db)
```

That is not a track dependency. It is a `(track, fx)` pair with a lookup in the
middle, and `core/rs5k.lua` already speaks exactly that language. Feed those
call sites a container address instead and they work unchanged.

So the work is not 115 changes. It is one abstraction plus a short list of
things that genuinely need a track:

| # | Genuinely track-shaped | Where |
|---|---|---|
| 1 | Lane label comes from the track name | `build_lane_auto_names` |
| 2 | Lane selection follows track selection | 9 `SetOnlyTrackSelected` sites, sequencer + manager |
| 3 | MIDI routing: bus, sends, note filters | `engine_ensure_bus*`, `core/seq_bus.lua` |
| 4 | MIDI export writes one item per lane track | `sequencer_view.lua:3698` |
| 5 | Rack detection = folder parent | `get_selected_rack_parent_track`, two copies |
| 6 | Rack construction | `build_rs5k_rack` (browser), empty-kit builder (manager) |
| 7 | Manager rows built from child tracks | `collect_rows` via `each_child_track` |
| 8 | Save kit iterates rows | `save_current_kit` |
| 9 | Drag-and-drop resolves to a track | `resolve_native_drop_track` |

Nine problems, not a hundred. Item 3 mostly *disappears* in container mode: with
every RS5K on one track there is nothing to route to, so no bus, no sends, no
note filters.

---

## Phases

Each phase is meant to be shippable on its own. Phase 1 in particular should go
out and be lived with before anything is built on it.

### Phase 1 — the Lane layer (no behaviour change)

A pure refactor. Introduce one representation of a lane:

```lua
-- core/lane.lua
-- { track = MediaTrack, fx = number, index = 1..16 }
```

with a resolver per rack style, and route every existing `(lane_track, lane_fx)`
pair through it. Track mode returns the child track and its RS5K; that is what
happens today, only named.

Rules that matter more than the code:

- **`fx` is never stored.** The resolver returns it, callers use it immediately
  and throw it away. This is the address-volatility constraint, enforced by
  shape rather than by everyone remembering.
- No new behaviour, no new UI, no container anywhere. If this phase changes what
  the program does, it has gone wrong.

Verification: the existing suite still passes, and a rack behaves identically —
sequencer, manager, export. Add `tests/test_lane.lua` for the address arithmetic
(pure maths, no REAPER needed), including the case that caught the probe: the
address changes when the top-level count does.

**Ship this on its own.** It is the whole risk reduction of the project: a
refactor that changes nothing is easy to trust, and everything after it is
smaller because of it.

### Phase 2 — rack identity

Today a rack is "a folder track". Add a second answer without disturbing the
first.

- `Rack.of(track)` → `{ style = "tracks" | "container", parent, container_fx }`
- Track style: today's folder-parent walk, moved as-is.
- Container style: a track carrying a container marked as a Kit Maker rack.

Mark it with a named config parm on the container (the same trick the sequencer
already uses for its bus, `P_EXT:TK_KIT_MAKER_SEQ_BUS`), **not** by its name. A
user renames things; a marker survives that, and it is what keeps a user's own
RS5K on the same track from being mistaken for a pad.

This is the reason to use a container at all rather than sixteen loose FX: the
container is the boundary, so "which RS5Ks are the rack" has an answer instead
of a heuristic. `core/rs5k.lua` already carries scars from heuristic detection.

### Phase 3 — building a container rack

`build_rs5k_rack` gains a style. Container style: one track, one marked
container, sixteen RS5Ks inside it, note ranges as now.

This is where the three assumptions above get tested, in the cheapest possible
way: build one and play it.

**Settled: a pad's name lives in a JSON blob on the rack track, keyed by FX
GUID.**

    P_EXT:TK_KIT_MAKER_PADS -> { "{FX-GUID}": { name = "Kick", auto = "kick_909" } }

Renaming the FX instance was the other candidate and is the wrong one. The top
of `core/rs5k.lua` records why: RS5K detection reads the plugin name, and a
renamed instance was once invisible to the Browser, which responded by adding a
second one beside it. The FILE0 probe patches that, but making the pad name BE
the plugin name would put every pad of every container rack permanently into the
state that caused the bug. It also hands the user a way to rename a pad by
accident from REAPER's own FX window, with no way to tell that apart from a
rename we made -- which needs a second store anyway, at which point the blob is
already there.

Two values per pad, not one, because that is what the existing code needs:
`maybe_auto_name_pad_track` keeps the last name it set itself and only
overwrites when the current name still matches it, so a name you typed survives
the next sample. Today those two are `P_NAME` and
`P_EXT:TK_KIT_MAKER_PAD_AUTO_NAME` on the pad track; the blob is the same pair
with nowhere else to live.

Keyed by GUID rather than by pad number for the reason that runs through this
whole feature: positions move, GUIDs do not. A deleted pad leaves an orphan
entry, which is harmless and pruned on save.

The cost is that the blob is invisible: lose it and every pad falls back to the
name derived from its sample. That is a quiet degradation rather than a broken
rack, and names are derived from the sample most of the time anyway.

### Phase 4 — the sequencer

Mostly free after Phase 1. What is left:

- Lane labels (item 1): from the pad name of Phase 3 rather than a track name.
- Lane selection (item 2): with one track there is nothing to select, so
  selection becomes internal only. This is a small UX loss worth naming — today
  clicking a lane selects its track and the arrange view follows.
- Bus and sends (item 3): skipped entirely in container mode. The cleanup path
  must know this too, or it will hunt for a bus that was never made.
- MIDI export (item 4): one item with all notes rather than one per track. This
  is arguably better and definitely different.

### Phase 5 — the Kit Manager

`collect_rows` gets a second source: container children instead of child tracks.
The row shape barely changes — it already carries `track` and `fx` together.

Per-pad volume and pan already go through RS5K's own parameters, so they survive.
Per-pad record-arm does not: there is one track. Name that loss rather than
letting people find it.

### Phase 6 — Save kit and export

`save_current_kit` iterates rows, so it follows Phase 5 for free. Worth checking
that the slice-aware export (0.2.45) still reads its start/end offsets — it goes
through `RS5K.get_range(track, fx)`, so it should.

### Phase 7 — the edges

The unglamorous list, each of which would otherwise have surfaced as a bug
report. All done:

- **Dragging onto the rack track.** Kit Maker's own drag lands on the first
  empty pad -- a track cannot say which of sixteen was meant, and that is the
  answer a drum machine would give. Without it the sample went into a
  seventeenth sampler bolted to the end of the chain, outside the container,
  and the rack track was renamed after it.
- **A native (OS) drag** cannot be steered: REAPER loads the file itself,
  wherever it likes. All Kit Maker can do is refuse to rename the rack after it
  and say what to do instead. It does.
- **Relinking** already worked -- it runs off collect_rows and (track, fx) --
  but it stored the fx index in the relink item and used it frames later, after
  the user had been browsing for a folder. Inside a container that is an address
  and not a handle, so it is re-derived from the pad's GUID at the moment of
  use. That was the fourth appearance of the same mistake.
- **Undo** was already wrapped around building a container rack, including the
  failed case.
- **Deleting the container by hand** degrades to "not a rack": the marker
  resolves to nothing, `Rack.of` returns nil, and the views say there is no rack
  rather than misbehaving. Covered in test_rack.lua.

Not done, and a deliberate limit rather than a defect: a container rack can only
be created from one place, the Kits browser's kit-collection menu. The heatmap's
"Make rack" and the Kit Manager's empty-kit builder still make folder racks.

---

## Decisions needed before Phase 3

1. ~~**Pad naming**~~ — settled, see Phase 3: a GUID-keyed blob on the track.
2. **Conversion between styles** — "convert this rack to a container" will be
   asked for within a week of release. Out of scope for v1, but the data model
   should not make it impossible.
3. **Default** — the existing style stays the default, and container is chosen
   at creation. Changing the default would surprise everyone who has a workflow.
4. **REAPER 7 floor** — container racks need it. Track racks must keep working
   on 6, so the choice has to be hidden or refused on older versions.

## Done: pads are found by their plugin, not by their slot

Lane N is child N of the container. Anything added inside the container ahead of
the pads shifts every one of them, silently -- an EQ dropped in at the top makes
lane 1 address the EQ, lane 2 address pad 1, and so on down.

This is the third time this feature has met the same shape of problem, and the
answer each time has been the same: write down the thing that does not move. The
container is found by GUID and pad names are keyed by GUID; the pads themselves
still are not. The fix is an ordered list of pad GUIDs stored on the rack --
`Rack.pad_guids` already produces exactly that list at build time -- and
resolving lane N through it instead of by position.

Done. The rack writes the ordered pad GUIDs to `P_EXT:TK_KIT_MAKER_PAD_ORDER`
while it is being built -- the one moment position and identity are certainly
the same thing -- and `Lane.fx` treats the position as a hint: pad N is child N
in a rack nobody has rearranged, so the hint is right almost always and costs one
read. When it is wrong the pad is found by its GUID instead, and a pad whose
plugin has been deleted comes back empty rather than as its neighbour.

A rack built before this existed has no recorded order and falls back to
position, which is what it always had.

## Done in 0.2.51: every per-step parameter survives the export

Pitch, pan, volume, attack and release are all written as FX parameter
envelopes, and each one is handed back to the sequencer at play and returned at
stop. Nothing in the table below is outstanding any more; it is kept because it
is the clearest statement of what the split between notes and parameters costs,
and the next thing that lives on the sampler will have the same problem.

## The shape of it

Per-step expression is split between two homes, and only one of them travels.

Anything MIDI can carry is exported and is fine: velocity rides in the note-on,
gate and length are the note's length, substeps and echo are extra notes,
probability is decided while generating, and a groove moves the note in time.
That is most of what the sequencer does.

What is left lives on the sampler as a plugin parameter, and there the export is
uneven:

| | |
|---|---|
| **Pitch** | exported, as an FX parameter envelope |
| **Pan** | not exported |
| **Volume** | not exported |
| **Attack, Release** | not exported. Per LANE rather than per step -- only the Euclid page offers them, and `euclid_build_seq` writes the one value to every step |

So per-step pan and volume can be programmed and heard, and then quietly do
nothing in an exported pattern. Pitch already shows how to fix it: the export
writes a point on the pad's pitch envelope at each note, and
`set_rs5k_pitch_envelope_active` hands the parameter back and forth so the
envelope does not fight the sequencer while it plays. Pan and volume want the
same treatment. Attack and release need less -- a single point, or simply not
being reset.

Which is the other half of it: `stop_playback` sets all five back to zero. For a
Euclid lane with an attack that means stopping the sequencer silently undoes it,
and the exported item then plays with an attack of zero whatever was set when it
was written.

**Not to be confused with the shared-sampler problem.** An exported item plays
through the same RS5K the sequencer drives, so a plugin setting changed
afterwards -- Note-off is the one people hit -- changes how that item sounds.
That is inherent: a MIDI note cannot carry "and ignore note-offs". Elektron's
parameter locks have the same shape, and they do not survive a MIDI cable
either. Envelopes are the one thing that can pin a parameter to the pattern
rather than to the plugin, which is why extending them is worth doing.

## Not part of this feature: live per-step parameters lag

Noticed while testing the export. It affects both rack shapes and is written
down here only because this is where someone will look for it.

**What happens.** Per-step pitch, pan, volume, attack and release are applied by
`engine_sync`, which runs once per UI frame: it reads which step the engine has
reached and then sets the RS5K parameters from Lua. That is tens of
milliseconds of granularity, and it reacts *after* the step has begun. A 16th at
120 bpm is 125 ms, so the parameter can land well into the hit -- you hear the
start of the sample at the previous value. The notes themselves are fine: the
JSFX sends them with a sample offset. Velocity is fine too; it rides in the
note-on.

The MIDI export does not have this problem, because there the pitch is an FX
parameter envelope and the audio thread reads it exactly on the note. That is
why an exported pattern can sound *cleaner* than the one you were listening to.

**Why "put the sequencer in JSFX" is not the answer.** The sequencer's timing is
already in JSFX. The gap is that a JSFX cannot set another FX's parameters at
all -- there is no API for it. What it can do is send MIDI.

**The MIDI route, and what it costs.** RS5K responds to pitch bend, with a range
parameter that goes up to 12 semitones. So pitch could be sample-accurate. Two
constraints, and neither is small:

- **Range.** Per-step pitch is -24..+24. Pitch bend reaches 12. Either the range
  is cut in half or live and exported playback disagree outside it.
- **Pitch bend is a channel message.** Every `midisend` in the engine goes out
  on channel 1, so one bend would detune all sixteen pads. Per-lane channels
  would fix it -- and `lane_ch = i` is already assigned in two places in the
  JSFX and used nowhere, so this was considered once before.

**And per-lane channels bring their own problems:**

- A controller sending on channel 1 would only ever reach pad 1. Playing the
  rack by hand is something people do and like.
- Sixteen lanes would use the entire channel space exactly, leaving no headroom.
- Exported MIDI would arrive spread over sixteen channels.
- Every existing rack would need its samplers reconfigured, and pads carrying a
  non-RS5K instrument may have no channel filter at all.
- **It only solves pitch.** Pan, volume, attack and release would still need CC
  plus a parameter-modulation link per parameter per pad -- eighty links for one
  rack -- and CCs are channel messages too, so they inherit the same constraint.

**Open question if this is ever picked up:** can RS5K filter by MIDI channel?
The whole idea rests on it and it has not been checked.

**Verdict for now:** a known limitation, not a bug. Live per-step parameters are
approximate; the export is exact.

## Risks

- **Address volatility** is the one that produces silent wrongness rather than
  an error. Phase 1's "never store `fx`" rule is the mitigation, and it only
  works if it is never bent.
- **Two rack shapes forever.** The build cost is finite; the maintenance cost is
  not. Every future rack feature is now two features. This is the real price of
  the request and it should be a deliberate yes.
- **The routing loss** — one fader, no per-pad inserts, no stems. Per-pad volume
  and pan survive. Users should meet this at rack creation, not afterwards.
