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

The installed version is shown next to the **Kit Maker** title. **Right-click
that title** for this manual and for the two folders Kit Maker uses — they are
not the same place: the script is installed under `Scripts`, while presets and
the tag cache are written next to REAPER's own data.

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
  Right-click **+ Folder** for two more things: **Add subfolders as
  collections…** (below), and a **start folder** — once one is set, every browse
  dialog opens there instead of wherever you last browsed. Clear it from the
  same menu to hand control back to the recent folders.
- **Add subfolders as collections…** brings in a whole shelf at once. Pick the
  folder whose *subfolders* are your packs and each one arrives as its own
  collection, filed under a group named after the folder you picked.

  It goes one level and makes no attempt to work out which folder in your tree
  counts as "a pack" — that differs in every library, so your pick is the
  answer. Subfolders with no audio anywhere below them are skipped, so the
  Documentation and MIDI folders that ship beside the samples do not come in as
  empty collections; and the audio is counted through the whole subtree, so a
  pack that keeps its samples in a `WAV` folder is not mistaken for an empty
  one. It asks before adding, naming the count, and running it again over the
  same folder offers only what is new.
- One button toggles between the **List** and cover **Tiles** — it shows which
  you are in; right-click it for the tile size. Drag the splitter to resize.
- A second button cycles **Catalog → Split → Samples**, picking which panel gets
  the room on a narrow window; right-click steps back.
- Right-click a collection for the full menu: **Rename**, **Pin**, **Group**,
  **Move Up/Down**, **Include subfolders**, **Set / Clear / Open Cover**,
  **Open Folder** and **Remove Collection**.

#### Groups

A library outgrows a flat list. **Group** files a collection under a name, and
everything filed under that name gets one collapsible heading — so the dozen
packs from one vendor sit together instead of scattered through a list you have
to read twice.

- The **Group** submenu offers every group already in use, so filing a pack is
  picking a name rather than typing one. It also offers **the name of the folder
  the pack sits in** — sample libraries are already laid out that way, so for
  most packs that is the answer and it is one click. The field at the bottom is
  for a name that does not exist yet; it commits on **Enter**.
- **Right-click a heading** to rename it (also on Enter) or to **Ungroup these**,
  which empties the group without touching a single collection.
- Groups work in both the **List** and the **Tiles** view, and a folded heading
  stays folded across restarts.
- The **Groups** button in the top bar turns the headings off when you would
  rather have the plain list. It ignores the groups rather than undoing them, so
  everything you filed is still filed and comes back when you switch it on. The
  button only appears once you have a group — before that it would switch
  between two identical lists.
- Once you have a group, an **Ungrouped** heading marks where the groups stop.
  A group's contents end where the next heading begins, so without it the
  collections you have not filed run straight on from the last group as though
  they belonged to it — which in the tile view they certainly would look to:
  there are no rows to count and no indent to read, just tiles. It is drawn like
  a group's heading but carries a bullet instead of an arrow, because it does not
  fold; a folded one would hide nearly your whole library while you are still
  sorting it.
- **Pinned** collections stay at the very top. Pinning is about *reach*, so it
  cannot depend on scrolling to a group and unfolding it — which is what putting
  a pinned pack only inside its group would come to.

  A pinned pack that belongs to a group appears in **both** places: at the top,
  and under its group. Pinning is a shortcut, not a
  move, and a group that quietly stopped counting what you filed under it would
  be lying about its contents. A pinned pack with *no* group appears once, at the
  top — there is no second place for it to be.
- **Move Up / Move Down** move a collection within the run it is drawn in — its
  group, or the pinned block.

> Group names match regardless of capitalisation. *Samples from Mars* beside
> *Samples From Mars* would give two headings that look identical, each holding
> half of what you were looking for. The first spelling you used is the one that
> shows.

A collection with no group behaves exactly as before, so a library that never
uses this looks unchanged.

### Auditioning & using samples (right panel)

- **Filter by filename** narrows the list. **Flat list** drops the folder
  grouping and shows every sample in one run — useful once a tag filter has cut
  the collection down to a handful spread over many folders. **Folders** puts
  the grouping back, with **Expand / Collapse** for the headers.
- **Sort** — the button showing **A–Z** (or **Z–A**, **Short–Long**,
  **Long–Short**) orders the list by **Name** or by **Length**, either
  direction. It is labelled with the order you are looking at rather than with
  the word "Sort", so the row tells you how the list is arranged without being
  opened. Folder headers follow the same order as the names inside them.

  Numbers in names are read as numbers: *Kick 2* comes before *Kick 10*, and
  *909* sits after *808*. Sorted alphabetically, 10 lands in the middle of the
  ones and the sort looks broken.

  Sorting by **Length** reads the lengths a few files at a time while you watch
  — measuring a large pack in one go would freeze the window. Files not measured
  yet wait at the end of the list, in either direction, rather than pretending
  to be the shortest. Hover the button to see how far it has got.

> **The sort is for the list only.** Seeds pick samples by their position in the
> scan order, so the sorted list is a copy kept on the side. If it were not, the
> same seed over the same pack would build a different kit depending on how you
> had the browser sorted — on your machine and on someone else's, with nothing
> on screen to explain the difference. **Export filtered as kit** does follow the
> sort, because pad 1 should be the row at the top.
- Preview with **Audition** / **Stop**, a **volume** slider, and an **Auto**
  toggle that plays a sample the moment you click it (double-click always
  plays).
- **Walk the list from the keyboard**: arrows step one at a time, **Page Up /
  Down** move by a screenful, **Home / End** jump to the ends. With **Auto** on,
  each one plays as you land on it, and the selection stays centred so you can
  see what is coming rather than reading it off the bottom edge. The arrows go
  back to the text field whenever you are typing in one.
- Right-click a sample to **Load to RS5K on selected track**, drop it into a
  specific **rack slot**, or **Show in Explorer**.
- **Drag** a sample onto a REAPER track or a Kit Manager pad to load it into
  RS5K there.
- **Alt+drag** starts a real file drag instead, the kind the operating system
  handles — so the sample can be dropped into *any* sampler that accepts files
  (Kontakt, Battery, whatever you use), or into another program entirely. This
  one needs the **TK Native Helper** extension, installed separately through
  ReaPack; everything else works without it.

### Sample analysis & tags

Kit Maker can measure what a sample actually *sounds* like and tag it — its
frequency band, how sharp its attack is, how long it rings out, and whether it
is noise or pitched.

Analysis never starts on its own. One **Analyse** button in the control row,
beside the sort button, measures the selected collection:

- The label says where you are: **Analyse** with how far it has got, **Stop**
  while it is running, and **Analysed** with the count once the collection is
  done. Progress is drawn along the foot of the button while a job runs and is
  gone as soon as it ends.
- It runs in the background while you keep browsing, **pauses entirely while
  REAPER is recording** and eases off during playback.
- **Stop** at any moment — every sample measured so far is kept, and pressing
  Analyse again simply carries on with what is left.
- Results are cached per file, so a pack is only ever measured once.
  **Right-click** the button for *Re-analyse this collection*, *Re-analyse
  changed files*, the *Show tags panel* toggle and *Clear analysis cache*. Once
  everything is measured a plain click opens the same menu, since there is
  nothing left to start.
- The button stays put in the **Heatmap** view, where the sort and folder
  buttons do not — the heatmap is built out of measured samples and shows
  nothing without them.
- Hover it to see how long each sample took, so you can tell a slow drive or
  format from a fast one.

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

**Channels** splits the collection into **MONO** and **STEREO**. Useful when
you are building for hardware: plenty of samplers and grooveboxes either refuse
a stereo file or sum it to mono, and summing is where the phase problems come
from. This one needed no new analysis — the channel count has always been
measured, since it decides whether the Space axis reports anything at all.

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

#### A cell as a Builder pool

Right-click a cell → **Add cell as Builder Pool**. The samples in that cell
become a pool and the Builder opens. Link a slot to it and that slot draws only
from that corner of the sound space — so "this pad gets something short and
bright, whatever else the kit does" is a thing you can state once and keep.

This is the only pool that is a fixed list of files rather than a folder: what
selects the samples is how they measure, not where they live. So it behaves a
little differently, on purpose:

- It has no folder list and no **Scan** — there is nothing to rescan it from.
- The list is stored *inside* a preset instead of being rebuilt on load, unlike
  every other pool.
- It is a snapshot. Re-analysing or adding samples does not change it; make a
  new one from the cell if you want the pack's current contents.

The name comes from where the cell sits — *Sub Legato*, *Air Short*, *Middle* —
and is yours to rename in the Builder.

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

### Slicing a loop across the pads

Select a sample and press **Slice** — the button beside Audition and Stop. The
strip under the list swaps from the tags panel to the slicer, and swaps back
with the same button. Right-clicking a sample and choosing **Slice to rack…**
does the same thing in one step.

It shares that strip on purpose. Slicing is not a form you fill in and confirm:
you listen, move a line, listen again. Keeping it there means choosing a sample,
auditioning it and cutting it are one place rather than three, and the transport
you already have does the listening.

**Nothing is written to disk.** Every pad gets the same file and its own start
and end point, the way a hardware sampler has always done it. That makes it
instant, and it means the cut points stay adjustable afterwards — which they
have to be, because a loop played with any swing does not put its hits on even
divisions.

Four ways to cut:

| Mode | When |
|------|------|
| **Cues** | The file carries its own slice points. Used by default when it does. |
| **Transients** | Find the hits and cut in front of each one. For anything played rather than programmed. |
| **Parts** | 2–64 equal pieces, whatever the length of the loop. |
| **Bars+grid** | Say how many bars and how fine a grid; the length is put back in. |

The **waveform** shows where the cuts land, with the slices as alternating
panels and each one numbered. That is the only way to answer the question you
actually have — *is this landing on the hits?* — and on a loop with any swing the
answer is usually no.

In **Transients** mode there are two sliders. **Sens** decides how quiet a hit
has to be before it counts; turn it down and the slices thin out. **Ofs** shifts
every detected point together, and is usually worth a few milliseconds negative:
a hit is only found once it has risen, so the cut lands slightly behind the
attack it was aiming at. That error is the same on every point, which is why one
slider fixes it and dragging them one at a time does not.

**Alt+drag** a cut point to move it, **Alt+double-click** to add one or take one
away. Every mode ends up as the same list of boundaries, so this works in all of
them — set a grid, then nudge the two lines that landed wrong.

Faint lines mark every boundary in the file, while the shaded panels are the
sixteen that will reach the pads. A long file has more boundaries than a rack
has pads, and the **Which 16** slider picks which of them go on; without it the
rest of the loop would be unreachable. Once a loop is paged like that the
waveform **zooms to the section you are looking at**, because sixty-four cut
points across one window is a picket fence rather than something you can aim at.

**Bars+grid** also reports the tempo your bar count implies. Call a four-second
loop four bars and it reads 240 BPM with a warning — the loop is probably one
bar, or it has silence on the end. It is the one number that catches a wrong bar
count.

**Slice to rack** builds the rack, and sits at the right of the mode buttons.

> **Cue points are what make a stitched kit work.** A stitched file is sixteen
> one-shots end to end, and they are not the same length — a 400 ms kick beside
> an 80 ms hat. Cut into sixteen equal parts, not one boundary lands right and
> every pad plays the tail of one sound and the head of the next. Those
> boundaries are written into the file, so a kit Kit Maker stitched slices back
> apart exactly, with each pad named after the cue it came from.

### Sending a collection onward

- From a **PACKS** collection (or its right-click menu): **Use for
  Explosion** sets it as the Explosion source, or **Add as Builder Pool**
  creates a pool from it.
- From a **KITS** collection: **Create Drum Rack (RS5K)** builds a
  ready-to-play rack in REAPER, mapped from note 36 up. A stitched WAV in the
  folder is left out — it is the whole kit in one file, not a pad sound.
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
| **Seed** | The number the random pick starts from. See below. |
| **Character** | Leans the pick towards a sound — dark, punchy, short — on the axes measured by the analyser. See below. |

### Seeds — rebuilding a kit, and sharing one

A computer's randomness is a fixed sequence; the **seed** is only where you
start reading it. Start at the same place and you get the same kit.

Every detonate runs on a seed, and the one it used is left in the field
afterwards. So the kit you liked and pressed past is never gone — untick **New
seed each detonate** and press again to get it back.

More usefully, it travels. The same seed over the same samples builds the same
kit on anyone's machine, so a good combination can be shared as a number rather
than as a folder of files.

That last part only holds if the samples really are the same, which is what the
**pack** code under the seed is for. It counts the files and reads their names.
Two people whose codes match will get the same kit from the same seed; if the
codes differ, one of you has an extra sample or a renamed one, and the seed will
build something else — correctly, but not what was meant.

Some fine print worth knowing:

- Kits in a batch are seeded consecutively, so kit 34 of seed 84213 is simply
  seed 84246 — one kit, shareable on its own.
- **Generate kit name** stays random on every press; it is a button you press
  until you like the answer. The name a *detonate* generates does follow the
  seed, so the same seed gives the same kit under the same name.
- Changing anything else — the slot pattern, the character bias, the max length
  — changes the kit too. The seed reproduces a roll of the dice, not a recipe.
- The **Builder** has the same thing, in its Batch section. There the seed sits
  on the kit definition rather than on the dialog, so a **preset carries its
  seed**: a saved Builder setup and its seed rebuild the same kits together.
  It reproduces more, too — the pools, the slots and the bias, not only the
  picks.
- Switch on the **Sources log** and the exported kit carries its own recipe:
  the log opens with the seed and the pack code. The sample paths further down
  only mean anything on the machine that made the kit; those two lines are the
  part that travels.

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

### Undo

**Ctrl+Z**, or the button beside **+ Pool**, puts back what the last change
replaced. It covers the handful of actions that take your work away in one go:

- deleting a pool
- building slots from a pattern
- the quick 128-slot layout
- loading a preset over what you had
- deleting a preset — the file is written back exactly as it was

The button appears beside **+ Pool** only when there is something to undo, and
it names what that is — so you are not guessing whether it means the pool you
just deleted or the slots you replaced before that. The last eight changes are
kept.

Editing a field is *not* undoable — retyping an alias is not the mistake this is
for. It exists for the step you immediately regretted.

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
- **Seed** — the number the picks start from, with the pack code underneath.
  See *Seeds* under Explosion; it works the same here, and a preset saves it.
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

### Save kit

**Save kit** writes the rack out as a kit folder: the samples, the cover, and
the MIDI and sources logs. Pick the destination once and it is remembered.

Pads that play only part of their file — anything built with **Slice to rack**,
or trimmed by hand afterwards — are written out as that part, not as the whole
file. Inside REAPER a slice is two RS5K offsets and costs nothing, but a kit
folder has nowhere to put them: whatever loads it next sees files. Without this
a break chopped across sixteen pads would export as sixteen copies of the whole
break, correct in the project it came from and wrong everywhere else.

The audio is not re-encoded. The frames are copied out and the original format
header is written back unchanged, so bit depth, sample rate and channel count
come through exactly as they were.

> **Only WAV can be trimmed.** Trimming an mp3 or a flac would mean decoding and
> re-encoding it. Those are copied whole instead, and Save kit tells you which
> pads that happened to — in the exported kit they will play more than they do
> on the rack.

The **Sources log** records the trim for each pad: how long the slice is, where
in the original it starts, and how long the original was. That is what lets you
find your way back to the source file later.

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

### Groove

Each lane can be pulled off the grid by a **groove**: pick one, turn **Amount**
up, and the lane stops playing dead straight. Timing and velocity move together,
because half of what a sampled groove is, is how hard it was hit.

The pattern itself never moves. The groove is applied on the way out, so the
knob works while it plays and turning it back to 0% leaves your grid exactly as
it was — nothing to undo.

Seven grooves are built in:

| Groove | What it does |
|--------|--------------|
| **Swing 54 / 58 / 62 / 66** | 16ths, from barely there to a full triplet |
| **Shuffle 8ths** | only the off-beats; the 16ths stay straight |
| **Laid back** | the whole bar a shade behind |
| **Pushed** | the whole bar a shade ahead |

The swing figures follow the Akai scale, where 50% is straight and 66% is a
triplet — the same convention as Cubase, Logic and FL. Ableton and Reason run
swing from 0 to 100 instead, so the same number means a different amount there.
That is why each label also carries the actual shift: **+32%** of a step means
one thing everywhere.

**Your own grooves** go in `REAPER/TK_Kit_Maker/grooves` as ordinary `.mid` or
`.midi` files, and appear in the list under the built-in ones. That is the
format the groove libraries ship — an MPC 60 pack works as it comes. A file that
shares a name with a built-in replaces it.

The folder is created the first time Kit Maker looks at it, which is when you
first open a groove picker.

- **Subfolders are submenus.** Drop a pack in as it came and its folder becomes
  a heading you open — thirty grooves behind *TR707* rather than thirty
  near-identical lines in one scrolling list. Three levels are read, so a folder
  per vendor with the machines inside it also works.
- You keep track of where each groove came from, which matters because swing 62
  on an MPC 60 is not swing 62 on an SP-1200. Two packs can each carry a
  *Swing 62* without one of them quietly winning. The name that gets stored is
  the full one, `MPC60 / Swing 62`, so a saved pattern finds the same file again
  — that is what the picker shows once one is chosen.
- **Rescan grooves** sits at the foot of every groove picker, with *Open grooves
  folder* beside it. The list is read once and remembered, so use this after
  dropping new files in rather than restarting the script.

> **Why a groove can seem to do nothing.** Swing moves the *off-beats* — steps
> 2, 4, 6, 8 and so on. Steps 1, 5, 9 and 13 do not move at all, because that is
> what swing is. So a lane playing a kick on the beat comes out identical however
> far you turn the amount up, while a hi-hat on all sixteen steps shuffles hard.
> Hover the groove name to see which steps it moves: `>` is late, `<` is early,
> `.` is not moved. **Laid back** and **Pushed** are the two that move every
> step, so they change any pattern at all.

Some things worth knowing:

- The offsets are read as a *fraction of a step*, not as milliseconds, so a
  groove keeps its feel at any tempo and on a lane running at half or double
  speed.
- Only the first bar of a groove file is read. These packs are often four bars
  where the last one is a fill, and averaging that in would take the life out of
  the groove.
- **Export to MIDI carries the groove.** The exported notes sit where you hear
  them, not on the grid — so a shuffled pattern stays shuffled once it is an
  item in the arrange view.
- Built-in grooves are timing only. Velocity is what separates a groove someone
  played from a mathematical one, so a `.mid` brings dynamics and a built-in
  does not.

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
- **Echo & Groove** opens the lane's popup, holding the echo settings and the
  same per-lane **groove** the Step page has — see *Groove* above. Each page
  keeps its own, so a Euclid lane can shuffle while the same lane on the Step
  page stays straight.
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
