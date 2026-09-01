# TK Project Clips - Clip Launcher

A session view for REAPER. Version 0.6.0 - requires SWS, js_ReaScriptAPI and ReaImGui.

## What it is

The Launcher is a view in TK Project Clips, next to Items, Source Media and Automation. It gives you a grid: one lane per track, one row per scene. Clips play in time with your song, on the project's own bar grid, and a launched clip takes over only its own track - every other track keeps playing the arrangement.

## How it works

- Every track in your project is a lane, in track order. There is nothing to set up and no separate list to keep in step.
- A lane's clips live on a hidden track that sends into your real track, so a clip is heard through that track's FX chain, EQ and sends. Your own track is never given items.
- That hidden track is made when the lane gets its first clip and removed again when it loses its last, so a project you never launched anything in carries nothing extra.
- Your clips are stored as muted items on the hidden track. They are saved with your project.
- Launching places the clip on the timeline ahead of the play cursor, exactly on the boundary, and mutes that track's arrangement items for as long as the clip owns the track.
- All hidden tracks sit in a folder named TK LAUNCHER, kept at the end of the track list.

## Getting started

- Select an item in the arrange view and click an empty slot, or drag a file onto it.
- Click the clip to launch it. Playback starts by itself if the transport is stopped.

Faster: put the edit cursor on a section of your song and press **+ Scene**. Whatever each track is playing there becomes a row.

## Filling slots

| Source | How |
| --- | --- |
| Arrange view | Select one or more items, then click an empty slot. Several items fill consecutive rows. |
| TK Media Browser / Workbench browser | Drag a file straight onto a slot. |
| Media Explorer, Windows Explorer | Drag a file onto a slot. |
| Any file | Right-click a slot, Add file... |
| Nothing at all | Right-click a slot, New empty MIDI clip: one, two, four or eight bars, or as long as the scene it sits in. |
| Another slot | Alt-drag a clip onto it to move it; hold Ctrl while dropping to copy. |
| Arrange automation item | Select exactly one automation item, then click an empty slot in the matching automation lane. |

Docked or floating both work. If an OS drag never arrives on your system, note that the TK browsers announce what they are dragging themselves rather than relying on one, so that route does not depend on it.

A clip that was trimmed in the arrange loops the length you trimmed it to, not the whole file. Audio dropped in from a file is stretched to the project tempo when Sync BPM is on, reading the tempo from the file's metadata or its name.

## Playing

| Action | Mouse | Keyboard |
| --- | --- | --- |
| Launch a clip | Click it | Q W E R T Y U I / A S D F G H J K / Z X C V B N M , for the first three rows of the first eight lanes |
| Launch a scene | Click the row number | 1 - 0 |
| Move the outlined cell | Click a cell | Arrow keys |
| Launch the outlined cell | - | Enter |
| Stop a lane | Click the lane's stop button | Shift with any of the above |
| Stop everything | Stop all, or the square beside the bar count in the corner of the grid | Shift + a number key |
| Empty a slot | Right-click, Clear slot | Delete or Backspace |

Clips wait for the next boundary, so they always land in time. An empty slot in a scene means "this track is not part of it" and stops that lane on the same boundary. Ctrl or Alt held means the key is a shortcut, not a clip - Ctrl+Z still undoes.

## MIDI control

Open **MIDI Setup** to control clips, scenes and Launcher commands from a MIDI keyboard or pad controller. Switch on **MIDI enabled**, choose the input device, and set the channel to **Omni** or to the one channel your controller sends on. Then pick a layout.

| Layout | What it does |
| --- | --- |
| Keyboard | Consecutive notes from the Base note across the grid. **Scene per octave** gives each octave a scene; **One octave - active scene** keeps twelve keys on the scene the bank points at. |
| Pads | A bank of eight. **Clips** puts them on one row of the grid, **Scenes** turns them into eight scene buttons. |
| Custom Grid | Any number of rows and columns, to match the pads you have. **Lanes across** or **Scenes across** decides which way the grid is read. |
| Launchpad | An 8 x 8 grid whose rows step by ten or sixteen, with the strip down the right hand side launching scenes - and the pads lit from the grid. See below. |

Use **Learn** beside Base note, or beside any command, then play the note or pad you want to assign. A note or CC that is already taken by another command is moved rather than doubled up, so nothing ends up doing two things at once.

| Command | What it does |
| --- | --- |
| Previous / Next lane bank | Moves the mapping a bank sideways, through the lanes of a project wider than your controller. |
| Previous / Next scene bank | The same downwards, through the scenes. |
| Launch active scene | The first scene of the current bank. |
| Stop active lane | The first lane of the current bank, on the next boundary. |
| Stop all | Every lane returns to the arrangement on the next boundary. |
| Record | The same button as in the toolbar: keep what you play instead of clearing it away. |
| Launch scene 1 to 32 | One entry per row, for a controller with buttons to spare. |

The bank readout under the layout says which lanes and scenes the controller is on at that moment, so you can see where a bank step has taken you. Holding a pad works too: a clip whose Trigger is **Hold to play** sounds while the pad is held and stops when you let go, exactly as with the mouse.

The MIDI Setup window stays open while you work; close it with the red button or Escape while it has focus. Save the whole setup as a preset to reuse the controller, layout, bank and learned assignments in another session. Presets can be loaded or deleted from the same window.

### Launchpad

A Launchpad does not lay its pads out as consecutive notes: its rows step by ten (Mini MK3, X, Pro MK3 and the RGB MK2, pads 11 to 88) or by sixteen (the older S and Mini, 0 to 119). Pick **Launchpad** as the layout and then the family, and the grid follows. **Top left pad** and **A row further down** are there for a board that numbers itself differently; leave them alone and the family decides.

Choose a **MIDI output** and switch on **Light the pads**. On Windows the port a DAW is meant to use is the second one, usually called MIDIOUT2. From then on the grid shows what the launcher knows: an empty slot is dark, a filled one glows in its clip's colour, the clip that is playing is bright, one waiting for its bar line blinks, and an armed track blinks red. The strip on the right lights for scenes that have something in them. Only pads that change colour are sent, so the board keeps up.

**Mode** decides how much of the board the Launcher takes over, and MK3 boards give you the choice:

- **DAW mode** switches on the Session layout and lights the Session button, which is what Ableton and PlayTime do. The board stays itself: its Session and Custom buttons keep working and simply tell the Launcher that you pressed them, and its second MIDI port stays free for playing an instrument. This is the default. In this mode the strip on the right sends and receives control changes rather than notes, which the Launcher handles for you.
- **Programmer mode** hands the whole surface over. Novation's own reference is blunt about the cost: while it is on, the board's Setup entry is disabled and it only returns to normal operation when it is switched back. Use it only if DAW mode will not talk to your board.

Either way the mode is sent when the lights go on and undone when the Launcher closes; **Send mode again** asks a second time, for a board that was unplugged and put back.

On the RGB boards the flashing and pulsing is done by the board itself - a clip waiting for its bar line flashes, the one that is playing pulses - so those pads are set once instead of being switched on and off from the script.

An S or a Mini MK1 has only red and green lamps, so on those the colour is the state rather than the clip's own colour: dark, green, amber, red.

**Test pattern** paints the grid in a known order - row 1 red, then orange, yellow, green, cyan, blue, purple, white, with the left half bright and the right half dim - so that what you see says whether the top left pad, the row step and the colours are right on your board.

## What a click does

Each clip decides for itself, under **Trigger** in its right-click menu.

| Trigger | What a second click does |
| --- | --- |
| Click starts, click stops | Stops it on the next bar line. This is the default. |
| Click starts, click restarts | Fires it again from the top. |
| Hold to play | There is no second click: the clip plays while the mouse is held and stops the moment you let go. |

Hold to play stops on the beat you release, not on the next bar line, so it is a gate rather than a launch. That needs an effect in the signal path, because a clip is already written onto the timeline and buffered by the time you let go. The Launcher writes a small JSFX called **TK Clip Gate**, installs it, and puts it on the lanes that need one. Lanes with no held clip never get it, and it is taken off again when the last one is changed back.

An automation clip needs none of that: there is no sound to shut, so the curve simply ends where you let go and the parameter falls back to the track's own envelope. Let go before the bar line and the launch is cancelled outright rather than playing a sliver of itself.

## Clip options

Right-click any clip. The menu is grouped: what to do with it now, when it plays, how it sounds, what it is called, what is in it, and getting it out.

| Option | What it does |
| --- | --- |
| Launch / Stop lane | The same as clicking, from the menu. |
| Trigger | See above. |
| Loop clip | On: the clip repeats. Off: it plays once. |
| When it has played / Play Nx | Follow action: after N rounds it hands over. **Next scene** is the row straight below, empty or not - a lane with nothing there sits that scene out, and sitting one out means stopping. **Next scene with a clip** walks past the empty rows instead, and round to the top when there is nothing below. Then the previous scene, the first, a random row this lane has filled, itself, or stop. Nothing happens while the **Follow actions** switch is off; the menu says so and offers to switch it back on. |
| Retrigger every | For one-shots: fires the clip on a grid from 1/16 to 2 bars. Below the divisions you can switch individual steps of the bar on and off, so a snare can sit on 2 and 4. Steps are anchored to the project grid, so the pattern lands the same way whenever you start it. |
| Gain | Level for this clip, adjustable while it plays. It sits before the track's FX. |
| Speed | 0.25x to 2x, in six steps. Pitch is preserved. The setting multiplies whatever rate the clip already had, so tempo matching still holds. |
| Tempo | Stretched to the project, or played at its own recorded speed. |
| Key | For MIDI clips: what key the Launcher thinks it is in, and what to do about it. See Session key. |
| Rename / Colour | A name and colour of your own. The cell, its waveform and its play marker follow the colour; without one the clip uses the track colour. |
| Edit in MIDI editor | Opens a MIDI clip in REAPER's editor. Its lane is shown for as long as the editor is open, because an action will not touch an item on a track it cannot see. The cell picture follows the notes as you change them. |
| Replace with selected item / with file... | Swap the clip without clearing the slot first. |
| Write clip to arrangement at cursor | See Getting clips into the arrangement. |
| Clear slot | Empties it. If that was the lane's last clip, its hidden track goes too. |

## Recording into a slot

An empty slot can record what you play, the way a session view does. You need the track armed in REAPER first - the Launcher will tell you if it is not.

- Arm the track, then click the record circle on the empty slot. The transport starts if it was stopped.
- You get a count-in: recording punches in on the launch quantize, not on your click, so you have the same bar of run-up you would get launching a clip.
- Play.
- Click again to stop. Recording ends on the nearest bar line rather than the next one, because stopping is a reaction and the click lands a moment after the bar you meant to be your last.
- The clip appears in the slot by itself.

Right-click the slot and choose **Cancel recording into this slot** to call it off before it punches in. One lane records one thing at a time; starting a second slot on the same lane ends the first, and the two meet on the line with no gap.

The take is left on the arrangement as well, so you can keep it as an ordinary recording. Switch on **Clear the take after recording** in the settings and it is removed once the slot has its clip - the audio itself stays on disk either way.

## Scenes

A row is a section of your song. The number beside it is its length in bars, taken from the longest clip in the row rounded up; shorter clips loop to fill it. Right-click the row number for:

- **When it has played / Play Nx** - the same follow actions, one level up: the whole row moves on together.
- **Write this scene only, at cursor** - puts the row into the arrangement at the edit cursor, each clip on its own track. The cursor parks at the end, so scenes can be chained by hand.
- **Write the whole chain from here...** - walks the follow actions without playing them and writes the result, bounded by a length in bars you give.
- **Fill scene from arrangement at cursor** - the reverse: fills that row from what your tracks play there.

The **Follow actions** switch turns them off without clearing what they are set to - useful while building. A random follow action rolls the dice once when written, so you can generate a version, listen, and write again if you do not like it.

**One row more** and **One row fewer** change how many scenes the grid has.

## Lane headers

Each lane header carries its track's name and colour, and a row of controls.

| Control | What it does |
| --- | --- |
| Stop | Stops that lane on the next boundary. |
| S | Solo. This is REAPER's own solo on the real track, so it behaves the way solo does everywhere else. |
| A | Mutes that track's arrangement by hand, whether or not a clip is playing. Turn it off while a clip runs and you hear both layered. |
| FX | What the track already has, and a way to add more. At the top of the menu is the FX on that track: click one to open it in its own window, right-click one to bypass it without closing the menu. Below that: your TK FX Browser folders first, then Category, Developer, Folders, All plugins, Favorites, Recent and FX chains. The badge counts the effects on the track; right-click the badge itself for the chain. |
| Fader | The track's volume, if **Volume in the lane header** is on and the row is tall enough. It lets you collapse the track panel out of the way and still mix. |

Clicking the header selects the track. Right-click it for **Reset volume to 0 dB**, **Select target track**, **Name to look for in another project...** and **Clear this lane's clips**.

## Working alongside your arrangement

| Control | Effect |
| --- | --- |
| Launching a clip | Silences that track's arrangement for as long as the clip owns the track. |
| Mute song | Silences the whole arrangement while the clips keep playing. It mutes the items, not the tracks - muting a track would kill the clip too, because the clip arrives on a send. On by default; the choice is remembered per project. |
| Reset everything | Everything back at once: clips stopped, every muted item restored, song mute off. Playback keeps rolling. This is the recovery button - it reports how many items it put back. |

## Recording a performance

Nothing is rendered. What you get are ordinary items pointing at the same media, at the positions where you played them, with the lengths and cuts you performed.

- Put the edit cursor where the take should start. An arrangement loop is fine: the take is gathered from what was actually written, not from a window of time.
- Press Record. The count on the button includes clips still sounding.
- Play. Clips, scenes and follow actions are all captured.
- Press it again to stop. The take finishes the current bar and everything in it is trimmed to that line. Press once more to cut it off immediately instead.
- **Keep** moves the take onto your real tracks; **Discard** throws it away. The arrangement it replaced stays muted, so what you kept is what you heard.

An undecided take is discarded when the script closes. Keep is a single undo step.

## Getting clips into the arrangement

- Alt-drag a clip from the grid onto the arrange view. The edit cursor follows the snapped landing point while you drag, and the target track and bar are shown at the bottom of the window.
- Right-click a clip: **Write clip to arrangement at cursor**.
- Right-click a scene number to write that row, or the whole chain.

## Timing settings

Behind the **Timing** button, which shows the current quantize in its label.

| Setting | What it is |
| --- | --- |
| Launch quantize | The boundary clips wait for: off, one beat, or a fraction or multiple of a bar up to eight. The bar settings count the measures REAPER itself draws, so a time-signature change part way through the song cannot push the grid off the bar lines. |
| Clip run-up | How far ahead a clip is put on the timeline before it plays. REAPER reads media ahead of the play cursor and does not go back for anything that appears inside that window, so a clip given too little run-up loses the start of its own audio. A launch that cannot make the deadline waits for the next boundary instead of arriving damaged. Auto derives it from your media buffer and is the right choice for almost everyone. |
| Media buffer | REAPER's own setting, shown here because it decides the run-up. Smaller means you can launch closer to the beat; larger is safer on a slow disk or a heavy project. It does not affect latency. This is a global REAPER preference, and the panel can put back the value it had before the Launcher ever changed it. |

The run-up is also how close to the line you may click and still make it: click inside it and the launch takes the next boundary instead. It never goes below 0.3 seconds, whatever you set.

If a clip comes in late, raise the run-up one step. If launches too often slip to the next bar, lower your media buffer rather than the run-up.

## Layout

In the settings window, under Launcher.

| Setting | What it does |
| --- | --- |
| Scenes as columns | Turns the grid on its side, a lane per row and a scene per column, the way Bitwig lays it out. Clips keep their size. |
| Lane height follows the track | Gives each lane row the height REAPER gives its track, so the grid lines up with the track panel beside it. Envelope lanes under a track are counted, and the clip row fills that whole height. |
| Line up with the first track | Grows the header row until the first lane starts where its track does, so changing the ruler height does not put the two out of step. It can only add space; where the grid starts below the track, fold this window's own bars away instead. |
| Scroll with the arrange | Scrolling the arrange scrolls the grid to the same track. |
| and the arrange with the grid | The other way as well. Leave it off and the Launcher never moves your arrange by itself. |
| Colour lane headers | Fill each header with its track's colour instead of a stripe down its left edge. |
| Volume in the lane header | See Lane headers. |

The three lower settings need **Scenes as columns**, where a lane is a row and there is a track beside it to line up with.

The caret in the grid corner folds this window's own chrome away: title bar and toolbar, title bar only, toolbar only, or neither. **Waveform cells** draws each clip in its cell; turn it off for a compact grid of names only.

## Clip sets

The grid, your clips and their settings are saved with the project. A clip set saves them to a file instead, so the same rig can be loaded into another project.

Behind **Clip sets...**: **Save set...**, **Load a file...**, and a library organised in folders, one per production. Sets are matched to tracks by name; **Create missing tracks on load** makes the ones that are not there. Use **Name to look for in another project...** on a lane header where the track is called something else.

## Session key

The Launcher can read what key a MIDI clip is in - from its metadata, its file name, its folder, or the notes themselves - and fit clips to a key you set for the project.

- **This project works in:** sets the session key and mode. Clips outside it are marked.
- **Map the scale degrees** moves each note to the nearest degree of the session scale. **Transpose to the root only** shifts the whole clip instead, leaving its own mode intact.
- **Fit clips on import** does it as clips arrive; **Fit every clip now** does the lot in one go.
- Per clip, the **Key** submenu shows what was read and lets you correct it, send the clip **Back to its own key**, or **Read the key from its notes** again.

Transposed clips are marked in the grid, and the clip menu names the chords it found.

## Chord follow

Chord follow lets a MIDI clip follow a chord progression while it plays or is written to the arrangement. Open **Guide**, choose a **MIDI chord guide track**, then right-click the clip and choose **Chord follow**. The guide track may contain ordinary MIDI chord notes; **Create/update chord items** adds optional labelled items showing the chords the Launcher recognized.

- **Root** transposes each note by the shortest interval from the clip's detected root to the guide chord root at that point in time.
- **Scale degree** moves the notes by the corresponding degree of the session scale. This needs a session key and keeps the movement diatonic to that scale.
- **Off** leaves the clip unchanged.

Chord follow is applied to MIDI clips when they are launched, retriggered or written. It is separate from **Fit clips on import**: session-key fitting adapts a clip once to the project key, while chord follow responds to each chord along the timeline. The clip needs a known root under **Key**; audio clips are not transposed.

## Automation

A view of its own, beside the Launcher. It lists every automation item pool in the project as a card: the curve, its name, where it is used, how many instances there are, and its position and length in bars. Track and take envelopes both.

Double-click a card to go to its first instance. Right-click for **Insert at edit cursor** (pooled or unpooled), **Insert on another envelope**, **Select every instance**, **Go to** any instance by name, and a field to rename the pool.

## Automation clips

A clip can be a curve instead of a sound. Launching one puts an automation item on an envelope of that lane's track, on the same bar line every other clip lands on. Stopping the lane takes it away again and the parameter goes back to whatever the track's own automation says.

Curves do not sit in the track's lane. Each parameter gets a lane of its own underneath it, the way the arrange puts envelope lanes under a track, so a curve can run while the track's clip keeps playing. Their heights follow the matching envelope lanes in the arrange when **Lane height follows the track** is on.

| Making one | How |
| --- | --- |
| From a track lane | Right-click an empty cell, **New automation clip**, pick Volume, Pan or the plugin parameter you last touched, then a length. The lane is made for you and the clip lands in it. |
| From an automation lane | Right-click an empty cell, **New automation clip** and a length. The parameter is the one that lane is on. Clicking an empty cell makes a flat clip at the envelope's current value straight away. |
| An empty lane first | Right-click a lane header, **Add automation lane**. |
| From REAPER's own | **From an automation item**: the AutomationItems folder in your resource path, subfolders and all. The file says how long it is, so a four bar sweep arrives as a four bar clip. |
| From the arrange | Select exactly one automation item and click the plus in an empty slot of the lane for that same envelope. Its points, shapes, tension and length come with it. The Launcher says so when nothing is selected, when more than one is, or when the item belongs to another envelope. |

**Edit curve...** puts the clip on its envelope at the edit cursor, makes that envelope visible in a lane of its own and scrolls to it, so you draw with REAPER's own tools. **Curve done** takes the points back into the clip - including a length you changed by dragging the item's edge - and clears it out of the arrange. **Cancel** leaves the clip as it was. Both sit in the toolbar and in the clip's own menu, because the toolbar can be folded away.

**Save as automation item...** writes the curve into REAPER's AutomationItems folder, so a shape built here can be dropped on any envelope in any project and picked up again by **Load automation item**.

A curve is stored with its clip as the Launcher's own data - times as a fraction of the clip, values from 0 to 1 - rather than as a REAPER pool. That is what lets **Point at** send the same clip to another parameter, and what makes it stretch when you give the clip more bars or change the tempo.

### What launches what

- Launching a track clip starts the curves in its own row with it.
- Launching a curve moves only that lane to that row. The track keeps playing what it played, and so do the other automation lanes.
- **Follow parent clip** on a lane header switches the first of those off, so that lane only answers to its own cells.
- The square button on an automation lane header pauses it. Press it again, or launch one of its slots, to resume.
- Stopping a track stops its curves with it. Stopping one automation lane leaves the rest alone.
- A launch only ever starts things. Move a track to a row where an automation lane has nothing and that curve keeps running - stopping is something you ask for.

Trigger, Loop clip, When it has played, Play Nx, Rename, Colour, Write clip to arrangement and Clear slot all work as they do for any clip, and so does Hold to play. Gain, Speed, Tempo, Key, Chord follow and Retrigger are for media and are hidden. Automation clips travel in clip sets like anything else: the curve goes with the file and loading it back builds the lane again, though a clip is skipped if the plugin it points at is not on the track in the new project.

## Housekeeping

- **Show the lane tracks** reveals the hidden tracks in the arrange for a look; they stay out of the mixer.
- The grid, your clips and all their settings are saved with the project. Nothing is written to disk until you save.
- Files dropped in are referenced, not copied. Use REAPER's own "copy media into project folder" if you want the project self-contained.
- A clip whose media is gone, or a lane whose track was deleted, is marked in red and refuses to launch. Neither is removed automatically, because undoing the deletion brings it back.

## Known limits

- No warping. Clips do not follow tempo changes the way Ableton's do; tempo matching happens once, when a file is brought in.
- At fast tempos, when a bar is shorter than the run-up, a launch lands a boundary later than you clicked.
- Empty MIDI clips are a whole number of bars. There is no loop brace to drag a clip's length by hand.
- An automation clip is a whole number of bars too. A file whose own length is not one is rounded to the nearest bar and its curve stretched to fit.
- The keyboard grid addresses track lanes only. Automation lanes are mouse work.
- A curve launched inside a loop region starts where you launched it on every pass; media fills the stretch before it, automation does not.
- Where a curve lands on an envelope that already carries automation items of its own, the Launcher leaves those alone rather than trimming them out of the way.
