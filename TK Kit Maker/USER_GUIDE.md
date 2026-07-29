# Kit Maker — User Guide

Browse, build and sequence sample drumkits — random kits, full-control kits,
and two built-in pattern sequencers.

*Kit Maker, by TK & Flurmechanik*

## The five tabs

| Tab | What it's for |
|-----|---------------|
| **Browser** | Organise sample packs & kits, audition, analyse and tag, send them onward. |
| **Explosion** | Point at a folder, get a finished random kit. |
| **Builder** | Define pools & slots yourself, batch-export variations. |
| **Step** | 16-lane step sequencer driving the kit's RS5K rack. |
| **Euclid** | Euclidean pattern generator per kit lane. |

A typical flow runs left to right across the tabs: **Browser** to collect and
audition your samples → **Explosion** or **Builder** to render kits into RS5K
racks → **Step** or **Euclid** to program patterns on those racks. The
**Kit Manager** button (top bar) opens a 4×4 rack window that ties it all
together. **Esc** or the red dot (top-right) closes the window; your **Theme**
choice is remembered.

---

## 1. Install & requirements

Install through **ReaPack** — the easiest route and it keeps the script
up to date:

1. In REAPER: **Extensions → ReaPack → Import repositories…** and paste the
   TK-Scripts repository URL:
   `https://raw.githubusercontent.com/TouristKiller/TK-Scripts/master/index.xml`
2. **Extensions → ReaPack → Browse packages…**, find **Kit Maker** (by TK &
   Flurmechanik) and click **Install**.
3. Run it from the **Actions** list (search for *Kit Maker*) — assign it a
   toolbar button or shortcut if you like.
4. Make sure the dependencies are installed via ReaPack too: **ReaImGui**
   (required — the window needs it to draw) and **SWS/CF** (recommended: folder
   pickers, audition, "open folder").

> Prefer a manual install? Unzip so the `TK Kit Maker` folder (with `core/`,
> `ui/`, `data/`) stays intact under `.../REAPER/Scripts/`, then load
> `TK_Kit_Maker.lua` via **Actions → New action → Load ReaScript…**.

> **Good to know** — The sequencers install a small JSFX engine on the kit
> track automatically, so timing stays tight even when the window is busy. If
> the Step/Euclid page says the engine isn't running, check that the kit
> track's FX aren't bypassed.

---

## 2. Browser

*Your library hub — collect folders, audition samples, send them onward.*

The Browser keeps two kinds of collections side by side. The **PACKS / KITS**
button top-left shows which you are in and switches to the other:

- **Sample packs** — raw folders of samples you browse and pull from
  (feeds Explosion & Builder).
- **Sample kits** — finished kits; from here you can build a playable
  **RS5K Drum Rack** in REAPER.

### Managing collections (left panel)

- **+ Folder** adds a collection; **Rescan** refreshes its file list.
  Right-click **+ Folder** to set a **start folder** — once one is set, every
  browse dialog opens there instead of wherever you last browsed. Clear it from
  the same menu to hand control back to the recent folders.
- One button toggles between the **List** and cover **Tiles** — it shows which
  you are in; right-click it for the tile size. Drag the splitter to resize.
- A second button cycles **Catalog → Split → Samples**, picking which panel gets
  the room on a narrow window; right-click steps back.
- Right-click a collection for the full menu: **Rename**, **Pin**,
  **Move Up/Down**, **Include subfolders**, **Set / Clear / Open Cover**,
  **Open Folder** and **Remove Collection**.

### Auditioning & using samples (right panel)

- **Filter by filename** narrows the list. **Flat list** drops the folder
  grouping and shows every sample in one run — useful once a tag filter has cut
  the collection down to a handful spread over many folders. **Folders** puts
  the grouping back, with **Expand / Collapse** for the headers.
- Preview with **Audition** / **Stop**, a **volume** slider, and an **Auto**
  toggle that plays a sample the moment you click it (double-click always
  plays).
- Right-click a sample to **Load to RS5K on selected track**, drop it into a
  specific **rack slot**, or **Show in Explorer**. Drag a sample onto a track
  to load it; hold **Alt** while dragging for REAPER's native file drag.

### Sample analysis & tags

Kit Maker can measure what a sample actually *sounds* like and tag it — its
frequency band, how sharp its attack is, how long it rings out, and whether it
is noise or pitched.

Analysis never starts on its own. Under the filter box sits a progress bar with
an **Analyse** button that measures the selected collection:

- It runs in the background while you keep browsing, **pauses entirely while
  REAPER is recording** and eases off during playback.
- **Stop** at any moment — every sample measured so far is kept, and pressing
  Analyse again simply carries on with what is left.
- Results are cached per file, so a pack is only ever measured once. The **⋯**
  menu holds *Re-analyse this collection*, *Re-analyse changed files*, the
  *Show tags panel* toggle and *Clear analysis cache*.
- When a run finishes the line reports how long each sample took, so you can
  tell a slow drive or format from a fast one.

*Re-analyse changed files* compares every sample with the file on disk and only
re-measures the ones that were edited or replaced. The sample you click on is
checked the same way, so a file you just re-rendered shows its new figures
rather than yesterday's.

The sample you click on is always measured immediately, so the **tags panel**
below the list fills in as you browse. It shows the labels as chips, the
spectrum across the seven bands (SUB → AIR), and where the sample sits on each
axis. Hover the panel for the raw numbers behind the labels.

### Filtering by tag

Next to the filename box sits **Tags**, which narrows the list by what the
samples sound like. Only the tags actually present in the collection are
offered, each with a count — a pack of kicks will not offer you AIR, and the
counts already take your other choices into account, so a chip showing 12
really does leave 12 when you click it.

Within an axis the tags are **or**'d (SUB *or* LOW); across axes they are
**and**'ed (SUB/LOW *and* SHORT). Tag filters are not remembered between
sessions — a forgotten filter hiding most of your pack is a bad way to start.

**Category** and **Source** are the exceptions: both are read off the path
rather than the audio, so they work on a pack you have not analysed yet.
Category is also the one axis where a sample can hold several labels at once —
an open hi-hat is a hi-hat too, so **Hihat** returns the open and closed ones
alike while **Open hihat** returns just the open. Its counts therefore add up to
more than the number of files.

The seventeen categories are **Kick · Snare · Hihat · Open hihat · Closed hihat
· Clap · Rim · Tom · Crash · Ride · Cymbal · Perc · Shaker · 808 · Bass · Vocal
· FX**, matched on the usual naming conventions (`BD`, `kik`, `OHH`, `CHH`,
`vox`, …). Anything the rules do not recognise is gathered under
**Uncategorised** at the end of the list — worth a look now and then, because
those same files will not respond to a Builder slot filter or an Explosion
pattern either.

Every other tag needs a measurement, so while one of those is selected the
unanalysed samples drop out of the list — the popup says how many.

> Source only recognises words that describe material rather than decorate a
> name — `acoustic`, `foley`, `808`, `LinnDrum`, Ludwig — so a kit called
> *Wooden Field Machine* is not mistaken for a room recording. The filename is
> read first and wins; if the word was only in a folder name the tag shows as
> `ACOUSTIC?` in the tags panel, because that is a guess about the pack rather
> than about the sample.

> **Filter here, weight there.** This is a real filter: ask for the noise hats
> and you get the noise hats. The **Character** setting in Explosion and Builder
> does the opposite on the same axes — it weights the pool instead of narrowing
> it, so a batch of kits keeps its variety. Searching and generating want
> different things; see *Character* under Explosion.

> **What is measured, and how far to trust it** — frequency band, transient and
> decay are direct measurements. Noise-vs-pitched is reliable, the finer
> DEFINED/CHROMATIC split is a judgement call. Dry/room/hall/wet only appears
> for **stereo** samples: on mono material there is nothing to tell a room apart
> from a naturally long tail, so Kit Maker says nothing rather than guessing.
> Texture (clean/warm/crunchy/filthy) is not measured yet.

### The heatmap

The **Heatmap** button next to the filter box swaps the file list for a grid:
instead of names, you see where your samples actually sit. **File list** puts
the names back.

Two measured axes span the grid and the third becomes a weighting slider
underneath; the two dropdowns pick which is which, from Frequency, Decay and
Transient. The grid runs **4×4 by default to match the pad layout**; the slider
beside the axis pickers takes it up to 8×8 for a finer look.

- The grid shows whatever the list is showing, so the **Tags** filter narrows it
  too — pick Kick there and the grid is a kick grid.
- Cell brightness is how much material sits there, weighted by the slider.
  Moving the slider re-shades the grid — it never removes samples from it, and
  **Focus** sets how sharply that weighting falls off.
- **Click** a cell to hear a sample from that region, **right-click** for the
  usual load/show options.
- Keep clicking the same cell to **walk through it**: you get its best match for
  the slider first, then the next, and so on through the whole cell without
  hearing a repeat. **Shift-click** steps back the other way; both wrap around,
  so you can always get back to the one you liked. Clicking another cell — or
  moving the slider — starts a fresh walk. The weighting still decides the
  order, so what you hear on the first click is unchanged.
- The cell you last played is ringed and reads **12/33** — where you are in that
  walk, out of how many samples the cell holds. On small tiles only the ring and
  the plain count fit; hover for the position and the filename.

> **The axes rescale to your selection.** Narrow to kicks and the frequency axis
> zooms in on the range those kicks actually occupy, so they spread over the
> whole grid instead of piling into one column. It means the axis ends read
> "the lowest and highest in *this* selection", not absolute values — which is
> what makes the grid useful for comparing samples of the same kind.

#### Make rack

At **4×4** the grid *is* a pad layout, so **Make rack** turns it into a kit in
one press: one sample per cell, pad 1 from the bottom-left cell through pad 16
at the top-right. With frequency across and decay up, that means pad 1 is the
darkest and shortest sound and pad 16 the brightest and longest, with the whole
range covered in between.

- Choose **Fill the selected rack** (the rack whose track is selected in REAPER)
  or **Create a new rack**. Filling replaces what a pad holds and never grows
  the rack; if you want a full sixteen, create a new one.
- **Export as a kit folder…** does the same picking but writes the samples to
  disk instead — copied and renamed, like any other Kit Maker export.
- Empty cells leave their pad empty — if your pack has nothing in a corner, the
  kit shows it.
- **Re-roll** keeps the layout and draws different samples: every pad holds on
  to its corner of the sound space. Press it until the contents suit you.
- The weighting slider applies to the picks too, so "spread the spectrum, but
  all punchy" is a single action.

#### Show kit

The other direction: **Show kit** marks where the selected rack's pads sit in
this pack. Each pad's number appears in the cell its sample falls into.

The axes deliberately stay on the *collection's* scale rather than fitting
themselves to the kit — a kit rescaled to its own range fills the grid no matter
what, and would hide the very thing you are looking for. Four percussion pads
bunched in one cell is why a kit sounds flat; an empty stretch of grid is what
it is missing. Click there to hear what would fill the gap.

> **Only meaningful on the collection the kit draws from.** Because the axes are
> scaled to what is on screen, a rack from somewhere else is measured with the
> wrong yardstick: its pads pile up against the edges and "clustered" stops
> meaning anything. Kit Maker says so in that case rather than letting it read
> as a finding. Pads that had to be pushed in from outside the range are drawn
> dimmed.

Right-click the button to re-read the rack after changing it. Samples the rack
uses that were never analysed are measured on the spot — sixteen files is a
moment's work.

### Sending a collection onward

- From a **PACKS** collection (or its right-click menu): **Use for
  Explosion** sets it as the Explosion source, or **Add as Builder Pool**
  creates a pool from it.
- From a **KITS** collection: **Create Drum Rack (RS5K)** builds a
  ready-to-play rack in REAPER, mapped from note 36 up.
- **Export … samples as a kit folder…** (right-click the collection you have
  open) copies what the file list is showing into a new kit folder, numbered and
  renamed like any other Kit Maker export. The filters *are* the selection:
  narrow a 213-sample pack with the tag filter and the filename box until the
  list holds the twelve you want, then export those twelve. The menu item names
  the count, so you can see what you are about to write.

  It only offers itself on the collection currently open, because that is the
  one the filters apply to. Notes are handed out from 36 upward; past 92 samples
  there are none left, so the note is left out of the filenames rather than
  repeated.
- Moved your samples? Missing folders show a **Relink** / **Auto relink**
  button; remembered locations relink future racks automatically.

---

## 3. Explosion

*The fastest route: point at a folder, hit Detonate, get a kit.*

1. **Source folder** — pick a folder of samples (toggle **Include
   subfolders**); a live count shows how many were found.
2. **Kit layout** — the **slot count** (1–128) and the **start note**; the note
   range is shown live.
3. **Slot pattern** *(optional)* — what kind of sample lands in each slot.
4. **Naming** *(optional)* — the **kit name** (empty = random), a **start word**
   with **Generate kit name** to build one around it, and a **name in filename**
   added to every copied sample.
5. **Export** — the **destination folder**, what gets picked and what comes out
   (see the table below), then **Detonate**. A result popup reports what was
   copied, with an **Open folder** button.

Steps 1–4 are about the kit; step 5 is about writing it out — which is why the
destination lives there, the same as in the Builder.

### Options worth knowing

| Control | What it does |
|---------|--------------|
| **Slot pattern** | Comma-separated categories or keywords (e.g. `Kick, Snare, Hihat, Clap`) assigned to slots in order and repeated to fill them all. Empty = any sample; unknown words match as "filename contains". The **+** button inserts known categories. |
| **Start word + Generate kit name** | Type an optional seed word, then **Generate kit name** to auto-name the kit (leave the seed empty for a fully random name). |
| **Stitched WAV + cues** | Also joins every sample into one WAV with an embedded cue point per slice — ready for slicers. WAV sources only; other formats are skipped. |
| **Max sample length (s)** | Samples longer than this are never picked (and stay out of the stitched WAV). 0 = no limit. |
| **Character** | Leans the pick towards a sound — dark, punchy, short — on the axes measured by the analyser. See below. |

### Character

Explosion and Builder can steer the random pick towards a *kind* of sound
instead of picking flat random. Three axes, each with a direction and a
strength: **Frequency** (SUB → AIR), **Decay** (SHORT → LEGATO) and
**Transient** (SOFT → IMPACT).

The crucial part: this **weights** the pool, it does not filter it. Ask for
dark and punchy and a batch of 50 kits still gives you 50 different kits — they
just all lean the same way. Nothing is ever ruled out, so you keep the happy
accidents.

- **Focus** sets how hard to lean. 0 leaves the pool untouched; 1 all but
  ignores anything off the mark.
- Samples that have not been analysed count as *average* on every axis: they
  stay in the running but are not favoured. Analyse the pack in the Browser
  first to get the full effect — the panel tells you how many are measured.
- In the Builder, individual slots can override the kit-wide setting through
  the **Char** column ("whole kit dark, but this one hat short and sharp").

---

## 4. Builder

*Full control: define pools and slots yourself, then batch-export.*

Start from **Fresh start** or load a preset. The page then walks the same way
Explosion does: **1 Pools → 2 Slots → 3 Export**, all three always on screen.

### Presets

The **Presets…** button sits above the steps, with the name of the preset you
are in beside it — saving and loading is a file operation rather than a step in
building a kit.

- **Save** (type a name) stores the current pools + slots; **Update**
  overwrites a listed one.
- **Load** restores a preset; **Delete** removes it. Presets also appear on the
  empty-start screen.

### Step 1 — Pools

A **pool** is a named group of one or more sample folders.

- **+ Pool**, then set the **Alias**, **+ Add folder**(s) and toggle
  **Subfolders**.
- **Mode**: *Repeat* (samples may be reused) or *Use up* (no repeats until the
  pool is exhausted, then reshuffle).
- **Scan** counts available samples. Missing folders can be **Relink**ed in
  place.

### Step 2 — Slots

Each row is one sound in the kit. Build the table with **+ Slot** / **+ 16
slots**; **Renumber notes** numbers them upward from note 36 (C2).

**From pattern…** is the quick route: type `Kick, Snare, Hihat, Clap`, set how
many slots you want, and every slot comes out with its filter already set — and
with the pool whose **alias matches the word**, so pools called Kick / Snare /
Hihat wire themselves up. A pool named `Snares` still answers to `Snare`. The
popup shows which pool each word found before you commit, and it replaces the
slots you have.

**Presets** in that popup holds the same ready-made patterns Explosion offers —
*Classic 4*, *Drum machine 16*, and so on — plus your own. Save a pattern on
either page and it turns up on the other.

| Column | Meaning |
|--------|---------|
| **#** | Slot number / order. |
| **Pool** | Which pool this slot draws from. Orange **(no pool)** = link one before exporting. |
| **Note / Pad** | MIDI note and pad number for the slot. |
| **Filter** | Restrict this slot to a category or a custom keyword; a live count shows how many pool samples match (red = none match). |
| **Char** | Optional per-slot character override; blank means the slot follows the kit-wide setting under Export. |
| **Lock** | Pin one exact file so that slot always uses it instead of a random pick. |

**Quick layout…** (next to the slot buttons) fills a full keyboard in one go:
white keys alternate between **pool A / B**, black keys all use **one pool**
(e.g. Kick / Snare / Hi-hat). It **replaces** the slots you have, and says so
with the count before you press it.

### Step 3 — Export

**Destination** comes first — where the kits are written, the same place
Explosion keeps it.

**Naming** — number style, note notation, whether to include the alias, and the
separator, with a live **Preview** of the resulting filename.

- **Kit name prefix** (empty = random) and a **Start word** + **Generate kit
  name** helper.
- **Kit count** (1–200) to make many variations in one run.
- Optional logs: **MIDI log**, **Sources log**, **Used-samples log** (avoids
  repeats across sessions), plus **Stitched WAV + cues** and **Max sample
  length**. The MIDI log is written in REAPER's note-name format (`36 Kick`),
  so it can be loaded in the MIDI editor under *File → Note names* — or read as
  a plain list of what sits on which note.
- A line above the button reports readiness — *"16 slots, all linked to a
  pool"*, or a warning naming how many have no pool, since those stay empty.
- **Batch export** runs with a progress bar; each kit is its own subfolder of
  copied, renamed samples.

---

## 5. Kit Manager (RS5K rack)

*The 4×4 pad window behind the playable racks.*

Open it with the **Kit Manager** button in the top bar. It shows the selected
kit's RS5K rack as a 4×4 pad grid and is where racks are created and maintained
— the Browser's **Create Drum Rack** and both sequencers all target this rack.

- **New Kit** creates a brand-new empty RS5K rack in REAPER.
- Per rack: **Rename kit**, a **Cover** image, **Rack color** and **Rack
  volume**.
- Per pad: load / replace a sample, set the **MIDI input**, a per-pad
  **Note-off** setting (also used to stop the sound on mouse release), and pad
  **auto-name**.
- **Relink** finds pads whose sample moved or whose drive letter changed — pick
  the new folder once and future racks relink automatically.

Racks name their MIDI notes after the instrument, so the piano roll reads
**Kick**, **Snare**, **Closed hihat** rather than C2, D2, F#2. Where the naming
rules recognise nothing, no name is set and REAPER goes on showing the pad
track's own name — the sample filename — so those rows never come up blank.

---

## 6. Step sequencer

*A 16-lane grid driving kit slots 1–16 on the selected rack.*

Select the kit's folder track first (the header will say so if you haven't).
Each of the 16 lanes is one kit slot; click cells to place steps. Lanes play
through the rack's RS5K instances in real time, and a JSFX engine keeps the
timing solid.

### Per-step editing

Open a lane (click its name; right-click toggles the editor) and pick a
**parameter mode** to draw values across its 16 steps:

| Mode | Effect |
|------|--------|
| **Velocity** | How hard each step hits. |
| **Gate / Length** | Note length per step (Gate needs RS5K note-off; hidden for one-shot lanes). |
| **Substeps** | Ratchets/rolls — retrigger a step several times. |
| **Pitch / Pan / Volume** | Per-step RS5K pitch, pan and level offsets. |
| **Probability** | Chance a step actually fires, for variation each loop. |
| **Step-mode mask** | A per-loop `x / .` mask (x = trigger, . = skip) so a step can play on some loop repeats and not others. |

### Per-lane controls

| Control | What it does |
|---------|--------------|
| **Solo / Mute** | Focus or silence a lane. |
| **One-shot / Retrig** | Play the whole sample ignoring gate, and choose retrigger behaviour. |
| **Note-off (obey)** | Whether the lane respects RS5K note-off (needed for Gate/Length to shorten). |
| **Speed** | Lane runs at 1×, 0.5× or 2× the master step rate. |
| **Direction** | Forward, reverse and other play orders per lane. |
| **Echo** | Built-in repeats with adjustable rate, count and velocity mode/delta. |
| **Copy / Paste / Clear** | Move lanes around; auto-name labels lanes from their samples. |

### Pattern pages, presets & playback

- Four **pattern pages** per kit; **copy** / **paste** a whole page. They work
  with or without a preset — without one they are kept on the kit track, so they
  survive closing the script.
- A global **pattern library**: **New**, **Save**, **Rename** and **Delete**
  presets, selectable per page. Saving a preset stores all four pages.
- Play in **pattern mode** (loop the page) or **song mode** (chain pages);
  **Host** follows REAPER's transport and tempo.
- **Export to MIDI**: left-click exports one pattern, right-click exports all
  four (the Step-Mode cycle); a separate control does pattern vs. song export.

---

## 7. Euclid sequencer

*Generative Euclidean rhythms per kit lane, on the same rack.*

Euclid shares the rack and lanes with the Step page but generates each lane's
rhythm mathematically: spread a number of hits (**Pulse**) as evenly as
possible across a number of **Steps**, then **Rotate** to shift the accent.
Select a lane to reveal its knob row.

| Knob | What it does |
|------|--------------|
| **Steps / Pulse / Rotate** | Pattern length, number of hits, and rotation of the pattern. |
| **Speed / Sub / Len** | Lane speed (0.5×/1×/2×), ratchet substeps, and active pattern length. |
| **Prob** | Per-lane probability that a hit fires. |
| **Vel / Gate** | Base velocity and note length for the lane. |
| **Pitch / Vol / Pan** | RS5K pitch, level and pan for the lane (needs an RS5K instance on the lane). |
| **Attack / Release** | RS5K amp envelope shaping per lane. |
| **Vel / Pitch / Vol randomisers** | "Dice" that add controlled randomness with an amount level and a seed; re-roll for a new variation while keeping the pattern. |

- Lane buttons mirror the Step page: **Solo**, **Mute**, **One-shot**,
  **Retrig**, **Note-off**.
- Its own preset library (**New**, **Save**, **Rename**, **Delete**), plus
  **Host** sync, **Export**, and a lane connection-lines toggle.

---

## 8. Good to know

- Exports always **copy** samples — your originals are never modified.
- Explosion, Builder and the Browser all fill the same kit structures and share
  one export engine, so a kit made one way behaves the same everywhere.
- Both sequencers store their patterns on the kit track itself, so each rack
  carries its own sequences.
- Presets, logs, the pattern library and the analysis cache live under
  `.../REAPER/TK_Kit_Maker/` alongside the script's data.
- Analysis is stored per file path, so the same sample is only ever measured
  once no matter how many collections point at it.

---

*Kit Maker — by TK & Flurmechanik · part of TK Scripts for REAPER*
