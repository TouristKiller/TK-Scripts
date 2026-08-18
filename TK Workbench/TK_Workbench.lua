-- @description TK Workbench
-- @author TouristKiller
-- @version 0.8.2
-- @changelog:
-- v0.8.2
--   + Idea Vault: An idea now fits itself to the project you load it into. A track template records no tempo of its own - not one TEMPO line, no stretch markers - so its items are plain seconds and REAPER has nothing to convert them from: a phrase captured at 120 landed in a project at 140 with its notes in the right place and its item boundaries in the wrong one. The sidecar is the one thing that knows what tempo it was played at, so positions, lengths and fades are scaled on the way in
--   + Idea Vault: Audio comes along without being transposed. The item is scaled and the take's playrate is moved the other way, so length times rate is unchanged and exactly the same piece of audio is used - only faster or slower, with the take's preserve-pitch flag holding the note where it was. MIDI takes keep their rate, because their notes are ticks and already play at the project tempo; only their item boundaries need moving
--   + Idea Vault: Track envelopes are scaled with the items. Their points sit on the project timeline in plain seconds, so automation used to stay behind where the performance had been. FX parameter envelopes are covered by the same pass, since REAPER counts those as track envelopes too. Take envelopes are deliberately left alone: their points live in take time, and length times rate came out unchanged
--   + Idea Vault: Captured items are stamped "Beats (auto-stretch at tempo changes)" rather than being left to inherit whatever the project they land in happens to be set to. That inherited setting is why the same idea behaved differently depending on where it went - and if it was Time, nothing adapted at all. Fitting on load handles the arrival; this handles every tempo change after it
--   + Idea Vault: The tempo checkbox is now named "Set project tempo to the idea's", which is what it does. It reads as the exception it is: items fit themselves to the project, and this bends the project to the idea instead - what you want when a new piece starts from one. It also moved to its own row: five controls on a single line ran past the right edge of a narrow panel, and there is nothing there to scroll with
-- v0.8.1
--   + Idea Vault: An idea recorded at another tempo now says so before you load it. A track template holds no tempo of its own - there is not one TEMPO line in one - so its items land against whatever tempo map the project already has, and the MIDI inside follows that map too. The preview you just heard obeyed Lock to tempo; the loaded template cannot, and that difference was invisible
--   + Idea Vault: "Match tempo on load" sets the project to the idea's tempo before the tracks arrive, which is the only moment it helps: item positions and lengths are stored in seconds, so a tempo set afterwards leaves them sitting where they no longer line up with the phrase they were played as. It is off by default because it changes the whole project, and it is one undo step together with the load
-- v0.8.0
--   + Idea Vault: A new module for the ideas you record in the morning and then never find again. It saves the selected track as a track template - MIDI items, envelopes and the FX chain all included - renders an audio preview beside it, and keeps the two together with your own description of the mood or style. This is the part an FX chain could never do: a chain carries plugins and nothing else, so it has no items, no MIDI and no sound to play back
--   + Idea Vault: Previews play locked to the project tempo without being transposed, so something recorded at 96 BPM sits in the grid of a song at 120. The tempo it was recorded at is written into a small file beside the preview rather than read back out of the audio, because whether a format carries a tempo tag a script can read varies per format and per REAPER build - and a preview playing at the wrong rate is worse than no preview at all
--   + Idea Vault: The preview format follows the project unless you pin one. Pinning copies the format out of the render dialog rather than building it in the panel, for the same reason Render Hub captures its presets instead of assembling them: the format is an opaque block of settings no script can safely write by hand. Set WavPack once, pin it, and every capture in every project uses it from then on
--   + Idea Vault: Capturing is one keystroke. TK_Idea_Capture.lua does the whole thing from a single dialog without opening Workbench, which is the point when the idea is still in your hands. The work itself lives in a shared core file that both the action and the module use, so the two cannot drift apart
--   + Idea Vault: A render that fails still leaves you the template. Template and preview are written separately and the capture says what it could not do, because losing a performance to a misconfigured codec would defeat the whole point of saving it
-- v0.7.2
--   + Plugin Browser: "Add to new track as send" is back, the way TK FX Browser and TK FX Browser Mini do it. Right-click a plugin for either the active track or every selected track: a new track is made holding that plugin, and each chosen track gets a send to it, in one undo step. It asks for the track's name with the plugin name filled in, and it can group the send tracks into a folder - the same two options under the same names as in the browser, so a preset set up there behaves the same here. Requested by Heavy
-- v0.7.1
--   + Render Hub: Renders more than one project in a batch. Projects you have open are listed on their own, and projects you do not have open can be added as files, so a folder of last year's work can be put through a new format without opening any of it by hand. Nothing is ever saved: an open tab is read as it stands and put back the way it was, and a file is opened over the front tab and left untouched on disk. The render is still correct, because REAPER's queue keeps a copy of every job the moment it is queued - which is exactly why none of this has to be written back into your projects. Requested by vik-tan
--   + Render Hub: The render queue is no longer invisible. The Run button says how many jobs are waiting and lists them when hovered, which matters because running the queue renders everything in it, including anything queued in an earlier session. Right-click it to open the queue and drop a job that should not be there; that deletes only REAPER's queued copy and leaves the project it came from alone
--   + Render Hub: One Render, one Queue, one Run. Render is always this project; Queue follows the ticks - the ticked projects if there are any, otherwise this one - and Run is the only thing that empties the queue. There used to be a second Render and a second Queue doing the same work by another route, and since your current project is itself one of the open tabs in that list, the two could not be told apart by what they did
--   + Render Hub: Rendering several presets over the project you have open no longer goes through the render queue. It used to queue one job per preset, which meant REAPER writing out a copy of the project and loading it back once per format - all of that to arrive at the project that was open the whole time. They are now rendered one after the other in place, and your render settings are put back afterwards. The queue is still there for what it is good at, which is setting work up now and running it later. Reported by BogdanS
--   + Render Hub: The ticked projects are rendered straight into themselves, with no queue in between. An open tab is switched to and rendered where it stands, a file is opened and rendered, and neither is written out as a queued copy first. Render already followed the ticked presets that way; it now follows the ticked projects too, so the two buttons beside each other no longer answer the same tick differently
--   + Render Hub: A preset can remember the mute and solo of every track, so "Instrumental" is a preset rather than something you set by hand each time. It is applied while that preset renders and put back afterwards. Clicking a preset to look at it never moves a fader - there would be no moment to undo that. Kept with the project rather than with the preset: track identities do not carry from one project to the next, and a preset that quietly muted nothing would render a full mix under the wrong name. Requested by BogdanS
--   + Render Hub: A preset can render a chosen set of regions, one file each, with $region and $regionnumber naming them, and the preview shows those names rather than the ones the project's own bounds would give - asked of REAPER the same way the render asks, so they are the names you will get. It is a list you pick rather than a capture of what is selected in the Region Manager: REAPER offers no documented way for a script to read that selection, and a list has the advantage of surviving a closed project and of being visible in the preset afterwards. Requested by BogdanS
--   + Render Hub: When REAPER will not name any output, the panel says which reason it is - no time selection, no regions in the project, no items selected, an empty range, or a region render matrix with nothing assigned - instead of listing the possibilities and leaving you to find out which. A wildcard that cannot resolve under the current bounds is pointed out as well, because REAPER drops an empty wildcard along with the space or hyphen beside it, so adding one looks like it did nothing at all
--   + Render Hub: The loudness check now picks up files from every route, not only from the Render button. What the queue is expected to write is noted when the jobs go in, which is the one moment the names are known - a queued project file still holds unresolved wildcards. A project that has never been saved is left out of that, because its name resolves to one thing when queued and another when rendered; it renders fine, it just cannot be predicted, and the list is marked so you can see which one that is
-- v0.7.0
--   + Sidechain: A new module for the routing nobody enjoys doing by hand. Select the track that should duck, click the track that should trigger it, and the send is made, the receiving track is given the channels it needs, a compressor is added and its key input is pointed at exactly those channels. The channel pair is whichever one is free rather than always 3/4, so it does not collide with a Control Room feed or anything else already using them. Requested by DaniloVillanova
--   + Sidechain: ReaComp is built in and set up for you. Any other compressor - Pro-C, Kotelnikov, a volume shaper - is stored by setting one up by hand once and capturing it. What gets remembered is not the channel its key input sat on but the distance from the pair it was captured on, so the same preset lands correctly whether the next sidechain ends up on 3/4 or on 7/8
--   + Sidechain: A preset can hold the plugin's settings or only the plugin and its routing. The first is ready to work the moment it lands; the second loads the compressor at its factory settings for you to dial in, which is lighter but leaves a plugin's own key input switch for you to turn on. Presets can be renamed, deleted, and re-read from a track once you have tweaked one further
--   + Sidechain: A second source on the same track feeds the compressor that is already there, so several triggers add up and one compressor ducks for all of them - which is what "duck the pad for the kick and the snare" actually needs. Ctrl-click gives that source its own channel pair and its own compressor instead, and which of the two is the default is a setting
--   + Sidechain: Everything already feeding the selected track is listed, whether this module made it or you did, with the channels and the send mode it uses. Removing one takes the send and the compressor that came with it, and leaves a send you made yourself alone
--   + Project Browser: Tiles no longer run under the scrollbar. Their width was measured before the scrolling list began and had a fixed 12 pixels taken off to stand in for the padding and the scrollbar - but a scrollbar is not a fixed width, it depends on the theme, and with "Hide scrollbars" switched on it is not there at all. The room is now measured inside the list, where it is already the truth in all three cases. The list rows were a fraction too wide for the same reason and are fixed with it. Reported by vik-tan
-- v0.6.90
--   + Render Hub: A new module for getting audio out of REAPER. The render window is a single dialog with settings you cannot name, wildcards you have to remember, and no sight of what you are about to get - so the panel shows the actual list of files the current settings would write. That list comes from REAPER itself rather than from a second guess at the pattern syntax, so it is what you will get, not an approximation of it. Type in the pattern and the list changes along with you
--   + Render Hub: Presets are captured from a project that is already set up, not assembled in the panel. The output format is an opaque block of settings that no script can safely write by hand, so the way to make a "Master WAV 24/48" or a "Stems per track" is to set the render window the way you want it once and press the plus. Clicking a preset loads it back into the project, and the preset matching what the project currently holds is marked LIVE. The capture window shows the source, bounds and format it is about to store, because REAPER only hands its render window settings to the project once that window is closed or its Save settings button is pressed - capturing too early would otherwise quietly store the previous state
--   + Render Hub: Tick several presets and they render in one pass. Each is queued with its own settings and the queue is run, after which the project is put back exactly as you left it. A master and an MP3 reference from a single click
--   + Render Hub: A preset can carry a tag from the Tags module, which selects those tracks before rendering. That is what a stem preset needs, since REAPER takes its stems from the track selection. The tag menu counts only the tracks in the project you have open - the tag store is shared by every project you have ever tagged in, so the raw number of tagged tracks would tell you nothing about this one
--   + Render Hub: After a render the files are checked. Integrated loudness, true peak and clipped samples are taken from REAPER's own render statistics where it reports them and measured from the file itself where it does not, then held against a delivery target: streaming at -14 LUFS, Apple Music at -16, broadcast R128 at -23, or a club master at -9. Clipping fails regardless of which target is chosen. Files are measured one per frame, so a long master never stalls the window
--   + Workbench: A module that is listed but not installed no longer reports an error. The list of module names lives in the main script and the module files travel separately, so an older package, a partial ReaPack update, or a name that ships ahead of its file left users with a wall of "no file ..." lines in the error log about something they could not act on and did not cause. A module that is simply not there is now passed over without a word. A module file that IS there and fails to load - a syntax error, a missing core file - still reports exactly as loudly as before, because that is a fault worth seeing. Reported by Warren
-- v0.6.87
--   + Notes: The delete button is back on screen. The drawing button added in 0.6.85 made six buttons on a note's header row, but the space kept for them was a fixed figure that fitted five - so the last one, delete, was pushed off the edge. The width is counted from the buttons that are actually there now, rather than being a number that has to be remembered
--   + Notes: When the panel is too narrow for the full row, the buttons fold into a single "..." menu instead of running off the edge. Colors, Font, Drawing, Duplicate and Delete all stay reachable at any width, and the menu button lights up while drawing is on, exactly as the pencil does
--   + Notes: The context row - Auto, Global, Project, Track, Item, Region - wraps onto a second or third line instead of running past the edge of a narrow panel. It used to divide the width by six but never below 48px a button, so under a 308px panel the row simply carried on past the side. How narrow a button may get is now measured from the longest label, so it holds at any font size or UI scale, and the rows are spread evenly rather than leaving a five and a one
--   + Notes: Notes are sized to the room they actually have. The width was measured outside the scrolling list and handed in, so once there were enough notes to scroll, every one of them was a scrollbar too wide - and how wide that is depends on the theme and on the "Hide scrollbars" setting, which makes it nothing at all. The width is now measured inside the list, which is right in every one of those cases
--   + Notes: Clearing the last note now also removes its drawing and resets its alignment. They were left behind, so clearing a note wiped the text but kept the doodle sitting on top of the empty page
-- v0.6.86
--   + Project Browser: Russian and other non-Latin project names are drawn correctly. A name that did not fit on one line was split at a byte rather than at a letter, and since Cyrillic takes two bytes per letter the split landed inside one - the halves were drawn as a placeholder box. It appeared to move when the window was resized because the split point moves with the width. Latin names were never affected, which is why it only showed up on Russian ones. The break also quietly swallowed a character, so a name lost its underscore or hyphen at the join. Reported by vik-tan
--   + Project Browser: The single letter shown on a tile that has no artwork - the one that flashes past while scrolling before the cover loads - was the first byte of the name rather than the first letter, so it too came out as a placeholder box on a Cyrillic name. Reported by vik-tan
--   + Same fix applied where any long name is shortened with an ellipsis: the shared text helper, Control Room, Send Studio, Plugin Browser and FX Chain Builder all cut off whole letters now instead of half of one
-- v0.6.85
--   + Plugin Browser: Masonry view, so screenshots sit like a brick wall instead of on a fixed grid. Tiles keep their own proportions rather than being squared off, the columns always fill the window exactly, and resizing re-lays them to fit. Requested by vik-tan
--   + Plugin Browser: Tile size is adjustable, and the layout keeps adapting to the window at every size rather than only at the one it was designed for
--   + Plugin Browser: Arrow keys move through the plugins, and the blue rectangle that used to appear around the list is gone. Pressing an arrow selected the child window itself and then did nothing, which looked like navigation that was broken rather than navigation that was never there. Reported by vik-tan
--   + Transport: Fixed the module erroring on open. It read a name that belonged to another module's file, so it was empty here - the kind of thing Lua only complains about at the moment the line runs. Reported by vik-tan
--   + Notes: Shares its notes with TK Notes. A note written in either script appears in the other and both can edit it, while each still works on its own without the other installed. Existing notes on both sides are copied into the shared form once, and where both scripts held a note on the same context both are kept - the Workbench shows the other one as an extra note block
--   + Notes: Text alignment, left, centre or right, set per note block rather than for the panel as a whole, and shared with TK Notes
--   + Notes: Drawing mode, with a colour, an adjustable thickness and an eraser, reached from the pencil button in a block's header. Drawings scroll with the text they were drawn over and are shared with TK Notes. The eraser splits a line rather than removing it whole, so rubbing out the middle of a stroke leaves both ends behind
-- v0.6.84
--   + Plugin Browser: "Custom Folders" stays in the source list even when you have none, saying where to make them. It used to be hidden until the file existed, which made the whole feature look as though it were not there - the folders are built in TK FX Browser and both read the same file, so there was nothing here to find until you already knew that
-- v0.6.83
--   + Control Room: Fixed the module refusing to load. Lua allows 200 local variables per file and this one was a handful short of it, so the actions added in the previous version tipped it over - a loop at the top of a file quietly claims five of those on its own. Nothing about the actions has changed; they are simply declared the way the rest of the file already was
-- v0.6.82
--   + Control Room: Discrete actions for Dim, Mono, Fold to Stereo, Mid, Side, Low, High and All Monitors Full, so they can go on a key or a control surface instead of only on a button. They appear in the action list as "TK Workbench: Control Room - ..." once ReaPack has installed them. Requested by DanialDevost
--   + Control Room: Each action does exactly what its footer button does, toggling back off when fired again - two ways to reach one switch, never two switches. The listening checks act on the monitor picked in the footer, or the only one if there is just one, and say so rather than guessing when several are available and none is chosen
--   + Workbench: The action bridge carries a verb now, not just "open this module". A script hands a module something to do and the module decides what it means, which is what makes key and control surface bindings possible for anything a module cares to expose. If the Workbench is not running the action starts it first, the same as the open actions always did
--   + Project Browser: A project name that runs onto a second line under a tile is drawn in the same colour as the first. It used to be dimmed, which made "Author_Title" read as though the title mattered less than the author - it is one name, not two things. Reported by vik-tan
--   + Project Browser: Search ignores capitals in Cyrillic and accented names, not only in English. Lua's own lowercase knows nothing beyond A-Z, so a Russian project only turned up when the capital was typed exactly as it appeared, which is not what a case-insensitive search is for. The Media Browser's filter goes through the same conversion. Reported by vik-tan
--   + Workbench: The lowercase used for searching handles Cyrillic and the accented Latin of western Europe, worked out from the UTF-8 bytes rather than a table of thousands of mappings, so it stays quick enough for a filter that runs on every keystroke. Anything it does not know is passed through untouched rather than mangled
-- v0.6.80
--   + Navigator: A module of its own. The bird's-eye map of the arrange was only available as a card inside Transport, and the block layout is one list for the whole module - so you could not have a full Transport in one place and a Navigator on its own in the other. Now it sits in the module list like any other and goes wherever you put it, the split view included. Requested by Halma
--   + Navigator: As a module it fills the pane instead of a fixed strip, so a tall pane gives every track its own row rather than squeezing them all into 120 pixels. Everything else is the same - drag to pan in both directions, the edges and the wheel to zoom time, Ctrl+wheel for track heights, and the fit button with its three zoom slots
--   + Navigator: It stays available as a Transport card, and both draw the same code from core/navigator rather than a copy each. Two copies of a thing this size drift apart, and the one that quietly misses a fix is the one nobody notices for months
-- v0.6.78
--   + Workbench: The smallest the window may be made no longer depends on auto-collapse. That floor was part of the auto-collapse code and disappeared along with it, so a window with the feature switched off could be dragged shut altogether - which is exactly the state that broke it. It belongs to the window rather than to that one feature, and applies either way now
--   + Project Browser: Fixed the panels being laid out past the bottom of the pane in a short window. Each of the list, the info panel and the preview panel had a minimum of its own, with nothing checking that they still fit together - so in a small window with the split view on they asked for close to 300 pixels of a 180 pixel pane and the last one ended up entirely outside it. What is actually left is now shared out, bottom panel first, and a panel that would come out a sliver is dropped so its room goes to the list instead
--   + Workbench: Fixed the window becoming unusable after being collapsed or dragged very small, and the run of errors that came with it - "ImGui_EndChild: Missing PopID()", "ImGui_PopID: expected a valid ImGui_Context*", and then a page of "ImGui_Detach" failures. Worse, the size is remembered, so a window left in that state failed again the moment it was reopened and looked for all the world like a script that would not start
--   + Workbench: ImGui hands back false from Begin when a window is collapsed or entirely off screen, meaning there is no point submitting anything to it - but it has pushed the window regardless and End still has to run. Three windows here skipped End on that path, and two more returned early without it, which leaves the window stack one deep and makes the next thing along report an error that has nothing to do with it. That is what sent every attempt at this chasing the Project Browser
--   + Workbench: If a window is already stuck in that state, deleting its file from REAPER/ReaImGui clears the remembered size. Each context has one, named after a hash, and the right one is found by searching that folder for the window's title
--   + Workbench: The error log says which instance wrote each line. Workbench and Workbench 2 share one workbench_errors.txt, so two of them running side by side read as one instance contradicting itself - and two lines a second apart look like cause and effect when they may be two unrelated faults in two different windows. That ambiguity was in the way of tracking down a crash report, which is a poor reason to lose a day
--   + Workbench: Repeated errors are counted rather than dropped. Only the first of a repeating error was ever written, so one failure and a thousand looked identical in the file; the line is written again as the count passes ten, a hundred and a thousand, which says whether something happened once or is happening every frame without filling the file with copies
--   + Workbench: A module can leave a note saying where it was, and an error that follows carries it. The Project Browser marks its list, tile grid, detail, playback, preview transport and settings popup, so a failure points at the panel that was drawing rather than only at the line that noticed. ImGui reports where it detects a broken id stack, which is not where the stack was broken
--   + Media Browser: A tile view, so the cover art your library already carries is worth looking at. One "Tile size" slider does it: all the way down is the list exactly as it was, and above that the number is roughly how wide a tile wants to be, with the column count following from the width of the pane. Art comes from the file's own tags first and from cover.jpg or folder.jpg beside it second, image files show themselves, and anything without art falls back to the coloured kind marker. Requested by Do613_9
--   + Media Browser: Folders are tiles too, because in a music library the album is the folder and that is the thing carrying the art. A folder shows its own cover.jpg where there is one, and otherwise borrows the art out of the first track inside it - most tagged music keeps the picture in the files and has no cover.jpg at all, so without that an album tile would sit empty while every track in it had one. The "up" entry does the same and stays a row, since it is navigation rather than something to look at. Tiles behave exactly like the rows always did - click, shift-click, drag and right-click all do the same things, and the "open folders on double-click" setting still applies - because they are the same item in a different frame. Only the tile rows in view are drawn, so a location with thousands of files costs what one with twenty costs
--   + Media Browser: Cover art loading was rebuilt first, because a grid asks for dozens of pictures where a single preview asked for one. Destroying an image was not enough on its own - while it stayed attached it kept occupying one of the context's attachment slots - which is the leak that filled the Project Browser's console with "ImGui_Attach: exceeded maximum object attachment limit". Nothing is thrown away while drawing either: the old code emptied the whole cache the moment it passed a limit, including pictures the frame it interrupted was still drawing with
--   + Media Browser: A screenful of new tiles now fills in over a frame or two rather than creating everything at once, and art that has gone unused for a couple of seconds is released, never below a floor that keeps what is on screen. The image preview used to keep exactly one picture and throw the rest away on the spot, which was fine for one panel and is not for a grid, so it lives under the same cap now
--   + Media Browser: The module sat on Lua's ceiling of 200 local variables per file, with nothing to spare - adding a single one made it refuse to load, which is what happened twice while Auto Key was being built. Its top level functions are now declared the way 86 of them already were, which costs no local at all, leaving 19 in use and the rest free. Nothing about it behaves differently; it is room to work in
-- v0.6.77
--   + Project Browser: A third switch next to the other two, for the name and path that follow the pointer over a project. Off, nothing appears on hover - in tile view the covers are labelled anyway, and in the list the name is already in the row. Folders keep their tooltip, since nothing else says where they lead. Requested by vik-tan
-- v0.6.76
--   + Workbench: Fixed the errors that follow opening a project while the Workbench is running - "BR_GetMediaItemGUID argument 1: expected MediaItem*", "CountProjectMarkers (ReaProject expected)", and the run of "expected a valid ImGui_Context*" that comes after them. Opening a project frees everything in the one being replaced, and the Workbench was still holding pointers to it from the snapshot it takes each frame
--   + Workbench: A pointer that has outlived what it names is still a value, so a plain "if item then" hands it straight to the API, which throws. The selected project, track and item are now checked before they are handed out and again where they are used. Notes was the module tripping over them, in its update as much as in its drawing, which is why it did not need to be on screen to do it
--   + Workbench: Checking a pointer is not by itself enough. A freed address can be handed straight back out to something in the project just opened, so the check passes while the pointer names the wrong item - which is why this showed up as an error only some of the time and as quietly wrong data the rest of it. Opening a project from the Project Browser now drops the snapshot outright instead, and the next frame builds a fresh one
--   + Workbench: Only the first error in one of those runs is real. An assertion inside ImGui takes the context down with it, so everything printed afterwards - the PopID complaints, the page of Detach failures - is wreckage rather than cause. That is what sent the earlier attempts at this looking in the wrong place
--   + Workbench: The selection snapshot is also taken after the modules have had their update rather than before it, so the drawing that follows works from the state the frame will actually show. That is a correctness fix in its own right and not what cures the above
--   + Project Browser: The preview transport reports what actually failed instead of "Preview controls unavailable". That message was hiding the cause while the broken id stack surfaced somewhere else entirely
-- v0.6.75
--   + Control Room: Monitor presets. REAPER keeps hardware output sends in the project, so a new project starts with no monitors at all and the routing has to be built from scratch every time. A preset holds the sends themselves - output, source channels and format, level and mute - and puts them back on the master in one click. Requested by BogdanS
--   + Control Room: Presets are stored with the Workbench settings rather than in the project, which is the point of them: they have to exist before the project has any routing. Aliases and per-monitor formats travel with them, and a monitor captured while folded brings the fold plugin back with it, so it is not silently pointing at a pair nothing feeds
--   + Control Room: Picking a preset loads it there and then. Monitors already pointing at the same output are updated, the missing ones are created, and the rest of the master is left alone. "Load exact" goes further and leaves nothing on the master but the preset, removing hardware output sends it does not mention. Both are a single undo step
--   + Control Room: Presets - choosing one used to only aim a separate Apply button, so the panel still showed the previous rig - and since Save takes whatever is on the master, one stray click wrote the old routing straight over the preset just picked. Loading on pick removes that trap: Save can now only ever agree with the name in the box
--   + Control Room: Presets - the panel lists what the selected preset holds, monitor by monitor: alias, output, format, listening mode and which master channels feed it, with anything not yet on the master called out
--   + Control Room: Presets now carry the listening mode of each monitor - Full, Mid, Side, Low, High, Fold to Stereo or a soloed speaker. Modes are held per output channel, so without this two presets on the same output shared one mode and changing it in either changed it in both. What gets stored is the mode itself and not the source channel it produces, because a check bus sits wherever there was room on that project's master and that number means nothing on the next one
--   + Control Room: Applying a preset sets the modes after the sends exist, so the source is worked out afresh and the check bus is rebuilt if the mode needs one. Presets saved before this keep the plain source they were captured with rather than being guessed at, and the whole apply is still a single undo step
--   + Control Room: The Setup window can be resized. It was pinned to a fixed size every frame, which on a tall screen wasted the room and on a short one buried the monitor list. Every tab already keeps its list in a panel that fills whatever is left, so the lists simply scroll inside the height you give it - drag the edge and the monitors, cues, mix sources and targets all follow
--   + Control Room: The size is remembered along with the position, restored when Setup opens rather than forced on every frame, and it cannot be dragged smaller than the tab row and a usable list need
--   + Control Room: Master format reaches 16 channels. Alongside the existing formats there are now 7.1.2 (10 ch), 7.1.4 (12 ch) and 9.1.6 (16 ch), so an immersive bed can be monitored, metered and folded like any other. Requested by BogdanS
--   + Control Room: The meter JSFX carries sixteen channels rather than eight, with a per-channel RMS readout for each. Loudness weighting follows ITU-R BS.1770-4 where it applies - front 1.0, surround and back 1.41, LFE out of the sum but still peak metered - and since BS.1770-4 predates the immersive beds and lists no coefficient for height channels, they take the 1.0 its own rule gives anything unlisted, which is what the Atmos loudness implementations use. Wide channels are front positions and take 1.0 too
--   + Control Room: Fold-down understands the new beds. Height channels fold in at their own level, on a Height slider next to the existing Centre and Surround ones, and the wide pair of a 9.1.6 bed folds at the surround level because it is an off-axis front position. The downmix JSFX went from sixteen to thirty-two channels, which is what a 16 channel bed plus the five check pairs above it needs
--   + Control Room: A master still carrying a downmix plugin from before this update refuses a bed wider than 7.1 and says so, rather than clamping to 7.1 and quietly folding as though the height and wide channels were not there. The same goes for the meter: it reads what the loaded instance actually carries instead of reading past its last parameter
--   + Control Room: Fixed the meter loading a new copy of the TK Control Room Meter JSFX every frame, stacking up dozens of them and opening a window for each. REAPER names a JS plugin after its description line when it recognises it and after its file path when it was added that way, and that path spells it with underscores - so on installs where the path name came back, the search for an already loaded meter matched nothing and added another one on top. Both spellings are now folded onto one before comparing, and the same was done for the Downmix plugin the fold bus uses, which had the identical fault waiting to happen
--   + Control Room: A track that already carries a pile of those duplicates is cleaned up on the spot - the first meter is kept and the rest are removed - so the fix does not leave you to clear them out by hand
--   + Workbench: Split view - a pin on the splitter, which keeps one pane on the module it holds: everything you open from then on lands in the other pane. Pinning the top pane to Transport and browsing with the bottom one is what this was asked for, but it works either way round and in side by side just as well. Requested on the forum
--   + Workbench: Clicking the pin walks through keeping the first pane, keeping the second, and keeping neither. The splitter grows an accent edge along the side it is holding, so which pane is kept reads from the divider itself, and the same choice sits in the split menu as "Keep top pane" / "Keep bottom pane" - wording that follows the layout, so it reads left and right when the split is side by side
--   + Workbench: Swapping the panes takes the pin with it, so what you pinned stays pinned rather than the pin staying behind and grabbing whatever moved in. Going Home and back keeps it too: the pinned module is set aside and put back in its pane, with the module you pick on the way out opening in the other one
--   + Project Browser: Fixed "ImGui_Attach: exceeded maximum object attachment limit" filling the console, and the freeze that came with it, on locations holding a lot of projects with cover art. Destroying an image was not enough - while it stayed attached it kept occupying one of the context's attachment slots - so the slots leaked away until there were none left. Restarting REAPER cleared it only because that starts a fresh context
--   + Project Browser: Cover loading was rebuilt along the lines TK FX Browser settled on for its screenshots. Nothing is created while drawing and nothing is thrown away while drawing either: a pass at the top of the frame loads a handful and detaches whatever has gone unused, so a screenful of tiles fills in over a frame or two instead of attaching dozens at once, and a tile that stays on screen keeps its image. The old code cleared the whole cache the moment it grew past a limit, including images the frame it interrupted was still drawing with, which is the likely source of the "EndChild: Missing PopID()" that followed
--   + Project Browser: Opening a project, making a preview and confirming a preview deletion now happen just before the next frame is built rather than in the middle of the one being drawn. All three block while REAPER keeps pumping its message loop, which can re-enter the script while a row or tile still has an id pushed and leave that stack crooked. Costs a frame and nothing else
--   + Project Browser: The Manage list pops its id whatever happens to the row, so a failure there can no longer take the frame down with it and hide what actually went wrong
--   + Project Browser: Two switches to hide the project info panel and the preview panel. Hidden panels give their height to the list rather than leaving a gap, and hiding the preview panel stops anything it was playing. Requested by vik-tan
-- v0.6.74
--   + Control Room: The listening checks - Mid, Side, Low, High and Fold to Stereo - have moved out of Setup and onto the footer, where DIM and MONO already were. They are things you reach for while mixing, not things you configure once, and hunting for them in a settings window was the wrong place for that. Suggested by BogdanS
--   + Control Room: They act on one monitor rather than the whole room, which is the point of them: dimming or mono-ing everything at once is what you want, but hearing the Side component of a drummer's cue feed is not. A row of monitor buttons above them picks which one, showing the alias you gave it, and ALL brings every monitor back - the same selector the S button on a lane always was, now in the open. With a single monitor there is nothing to choose and it is simply the target
--   + Control Room: Each check is its own off switch - pressing the mode a monitor is already in puts it back to Full - and a check that does not apply is disabled with a tooltip saying why, rather than vanishing and shifting the row along. Fold to Stereo is greyed out on a stereo monitor, the checks are greyed out until a monitor is picked, and ALL is greyed out while nothing is soloed
--   + Control Room: ALL is back on a fixed spot in the footer, having disappeared when the row became a fixed two by three grid
--   + Project Browser: A tile view, so the cover art a project already has is worth looking at. One "Tile size" slider does it: all the way down is the list exactly as it was, and above that the number is roughly how wide a tile wants to be, with the column count following from the width of the pane. Requested by vik-tan
--   + Project Browser: Folders keep their own full width rows above the tiles rather than becoming tiles themselves, which keeps navigating and browsing visually separate. Tiles behave like the rows always did - click selects, double-click opens, right-click gives the same menu - and the arrow keys learned the grid: left and right walk one item, up and down step a whole row. In the list the column count is one, so the arrows do exactly what they always did
--   + Project Browser: A "Min depth" setting next to Max depth, for hiding projects that sit loose in the scan root and keeping only what lives inside a folder. It counts the same way Max depth does, but it filters what is shown rather than what is scanned, so unlike Max depth it applies straight away instead of on the next scan
--   + Project Browser: A project without cover art now gets a centred "No image" in its tile instead of the initial of its name in the corner, stepping down to a shorter label and then to that initial when the tile is too small to fit it
--   + Project Browser: A "Rec" button next to Refresh shows the projects you opened most recently, read straight from REAPER's own history rather than from a scan, so it reaches projects that sit outside any location you added. It ignores the location, the folder view and the depth settings, because none of those mean anything for a flat list gathered from all over the disk, and entries pointing at something that has since been moved or deleted are left out instead of shown as dead rows. Requested by vik-tan
--   + Project Browser: A "Recent count" setting for how many of those to show, up to the fifty REAPER itself keeps
--   + Project Browser: Max depth, Min depth, Max items and Recent count all have tooltips now, since what they regulate was not obvious from the labels alone. Max items in particular is a safety brake rather than something to tune: reaching it stops the scan and the status line says "limited"
-- v0.6.72
--   + Media Browser: New: Auto Key, the same feature the standalone TK Media Browser has. Pick a target key on a small keyboard and everything you preview or insert is transposed onto it, so a library in mixed keys lines up with the track. The current key sits in the bottom right of the waveform panel - click it to open the options
--   + Media Browser: Auto Key - clicking a key on the keyboard auditions the selected sample in that key straight away, and switches Auto Key on rather than leaving the click silent. If something is already playing the pitch moves without restarting, so you can click through keys and hear it change instead of retriggering each time. There is a switch for anyone who would rather a click stayed quiet
--   + Media Browser: Auto Key - the tonic decides the shift and the mode does not, so picking C puts every sample's root on C and the same click always means the same thing. The shift takes the shortest way round the octave and never exceeds six semitones, so A minor to C minor is +3 rather than -9
--   + Media Browser: Auto Key - the source key comes from metadata first, and from the name second: the filename, and the folder it sits in, since libraries are often filed as Loops/C/bass.wav. Reading names is deliberately strict - "Am", "F#min", "Bb maj" and "(C)" are read, while "Ambient", "Feminine" and "(Gtr)" all start on a note letter and are refused. A loose "_C_" sits behind its own switch, off by default. A file whose key cannot be established is left alone rather than guessed at
--   + Media Browser: Auto Key - percussion is left alone by default, matched on whole words so that "custom" is not read as a tom. Transposition goes to the take's pitch rather than its playrate, so length and tempo sync are untouched, and the whole thing hangs off one function that preview and insert already shared - they cannot drift apart
-- v0.6.71
--   + Control Room: New meter bar sources. LUFS I/S/M draws integrated, short-term and momentary side by side instead of making you pick one, and Peak + LUFS I/S/M and RMS + LUFS I/S/M draw headroom and loudness together as two groups on the one scale - which is what you actually want while finishing a mix, since one tells you whether you are on level and the other whether you are about to clip. Reading three values off the meter JSFX costs no more than reading one, because it updates every slider in the same pass
--   + Control Room: Fixed the meter drawing a LUFS target line across bars reading dBFS. Peak and loudness are different scales - a -14 LUFS programme peaks nowhere near -14 dBFS - so on Peak and RMS the line marked nothing at all. It now belongs to the bar group it applies to, and stays away from the ones it does not
--   + Control Room: The coloured zones on the bars follow what is being measured. They were pinned to -18 for everything, which is a sensible headroom line for peak and meaningless for a loudness bar sitting against a -14 target. Peak and RMS keep -18 and 0; the LUFS sources take their warning from the target plus its tolerance, and their danger 3 LU above that. Reported by BogdanS
--   + Control Room: The target line is no longer drawn in the accent colour, which was also the colour of the bar fill underneath it - so it blended into every theme, not only the green one it was noticed in. It now derives a colour guaranteed to contrast with all three zone fills and the bar background, which matters most for the themes built from the user's REAPER theme where the accent can be anything, and it is dashed so it reads as a reference mark rather than as signal. Reported by BogdanS
--   + Control Room: Every bar is now its own hover and click target, so a narrow lane can still be read and reset. The tooltip gives the caption, the current value and the hold; clicking resets that bar's hold, which used to require hitting the small badge and was therefore impossible once the lanes got thin. The badge itself has a middle step as well: too narrow for name and value together, it now shows the value alone rather than falling straight back to a single letter
--   + Control Room: The footer is a fixed two by three grid - DIM, MONO and Setup above, Meter, Reset and the meter settings below - and it is drawn in both views. It used to be skipped entirely once the meter was open, which moved its controls to the top of the panel and left DIM, MONO and Setup unreachable from there. A button that does not apply is disabled rather than dropped, so nothing ever shifts along, and the three columns share the full width so the labels normally fit unabbreviated. Reported by BogdanS
--   + Control Room: The meter's value boxes are laid out in a grid instead of one tall column, balanced so six of them become three by two rather than five and a straggler. Stacked, they squeezed the bars into a sliver on anything but a very tall pane
-- v0.6.70
--   + Media browser: dragging a sample onto a window docked inside REAPER no longer hands the drag to the operating system. A docked window cannot receive an OS drop, so Windows passed it to the main window instead and the sample landed in the arrange
--   + Media browser: a drag is now advertised to other TK scripts while it lasts, so they can pick it up themselves. Dropping a sample on a TK Kit Maker rack pad therefore works with Kit Maker docked, which an OS drag can never do
--   + Media browser: releasing a dragged sample anywhere on MPL's RS5k manager window loads it into the pad selected there. Aiming at the pad itself is not possible while the manager is docked (it receives no drop at all then), so the selected pad stands in for it - the same target the right-click menu uses
--
-- v0.6.69
--   + Send Studio: A send can be given a name of its own. REAPER has no name field for a send - every list one appears in is labelled with the destination track - so three sends from one instrument to one sampler bus read as three identical rows, which is precisely what a template that switches articulation by MIDI channel is built out of. The name is typed in the "..." menu, or on a right-click of the name plate in strip view, and it is kept on the send itself, so it is saved with the project and stays with the send when the routing is reordered. Clearing it hands the track name back. It shows in Send Studio only - REAPER's own mixer goes on naming the track, as there is nothing in the send for it to read
--   + Send Studio: The channel button carries the MIDI channel. It only ever showed the audio pair, so a MIDI-only send read "MIDI > MIDI" no matter where it went, and the one number that told a set of sends apart was a popup away. It now reads "MIDI 1>3", or "1/2 > 1/2 | MIDI 1" when the send carries both, or "Off" when it carries neither
--   + Send Studio: Fixed copying sends losing their MIDI routing. Both audio channel fields were carried across but I_MIDIFLAGS was not, so pasting a channel-per-articulation set onto the next instrument gave the right number of sends with the channel mapping - the only thing separating them - stripped off. Custom names travel with the copy as well
--   + Send Studio: The extras popup - the return track's volume and pan, and now the rename - can be reached from the strip view as well, on a right-click of the name plate. It lived in the list view only, so the strips had no route to it at all
-- v0.6.68
--   + Control Room: Four checks added to the monitor modes - Mid, Side, Low Band and High Band. Mid is what sits in the centre of the mix on both speakers, Side the difference between them decoded back to a pair rather than summed, so a wide element keeps its position instead of collapsing to the middle, and Low Band and High Band are the two halves of a crossover you set yourself. A multichannel bed is folded down first, so the check is the same one whatever the main mix is
--   + Control Room: The checks all come off one downmix on the master rather than an instance each. It writes a pair per check onto spare master channels - fold-down, mid, side, low band, high band, in that order past the bed - and a pair nobody listens to is switched off rather than removed, so the ones in use never shift channel and the FX chain holds one plugin however many checks are running. Setup > Monitors names the pairs being listened to and carries the crossover frequency, and the Channel map names every pair
--   + Control Room: A MONO button next to DIM in the footer. Mono was there already but only per monitor in the right-click menu, and checking a room in mono means every monitor at once. It sums all of them, hands each its own mode back on the second press, and reads the state off the sends rather than remembering it, so a monitor put back by hand leaves the button telling the truth
-- v0.6.67
--   + Control Room: Fixed Fold to Stereo never being offered to the monitor that wants it. The mode was gated on the width of the monitor itself, so a stereo pair of speakers or a headphone output - the whole point of a fold-down check - could never be set to it, and the downmix was therefore never added to the master either. It now follows the master format instead: as soon as the main mix is Quad, 5.1 or 7.1, every monitor of at least stereo can be folded down to
--   + Control Room: Setup no longer reports the fold-down as "Not installed" while nothing is wrong. It is added to the master the moment a monitor asks for it, so the line reads "Not added yet" in normal text rather than a warning, and an Add button beside it puts the downmix on the master straight away for anyone who wants to set the centre, surround and LFE levels before switching a monitor over
--   + Control Room: If the downmix JSFX genuinely cannot be found, the message now says what to do about it instead of only stating the file name
--   + Control Room: Setup > Monitors has a Channel map, a row of cells per master channel and per hardware output saying what sits on each one - which speaker of the bed, the fold-down pair, and which monitor or cue reads or feeds it. A hardware channel claimed by two outputs at once turns red and is named underneath, along with any monitor reading past the end of the master, so a setup that quietly overlaps is something you see rather than something you work out
--   + Control Room: The lanes are grouped by what they actually are. Track and Master are the project busses, the monitors and cues are the physical outputs leaving the machine, and the metronome is neither - so each group gets its own heading and starts on its own row, and every card carries a coloured stripe on its left edge in the colour of its group. It can be switched off again with "Group lanes by bus type" in Setup > Monitors
--   + Control Room: The Mix tab of Setup is only there once a cue exists. Without one it held nothing but a line saying so, and a cue mix is meaningless until there is something to mix into. A cue whose track has been deleted no longer takes a lane either - a fader onto nothing is of no use to anyone - it stays in Setup > Cues where Clean Stale can take the record out
--   + Control Room: The meter draws the target you set. A line runs across the bars at the target level with a tolerance band around it - a couple of dB wide by default, or nothing at all if you set the tolerance to zero - so you can see where the mix is sitting instead of reading the number underneath and doing the sum yourself. It can be switched off in the meter settings
--   + Control Room: The meter is sizeable. Bar width narrows the channel bars and centres them, and Info size sets the height and the text size of the value boxes underneath - whatever they leave over goes to the meter, so a tall meter with two small readouts and a short meter with six large ones are both a slider away
--   + Control Room: The Media Browser's preview level is a lane of its own, under the physical outputs where it belongs. It rides the running preview straight away rather than only the next one, so a sample that comes in too loud can be pulled down while it plays
--   + Control Room: The bars can show something other than peak. "Bars show" in the meter settings picks Peak, RMS, LUFS-M, LUFS-S or LUFS-I, with RMS measured per channel by the meter JSFX over a 300 ms window. Peak and RMS keep a bar per speaker, but a LUFS reading is one weighted value for the whole bed and nothing is gained by printing it five times, so those modes draw a single wide bar - which is also where the target line finally means what it says
-- v0.6.66
--   + Control Room: Monitoring is no longer stereo only. A monitor output can be Mono, Stereo, Quad, 5.1 or 7.1, picked per monitor with a new Format row in Setup > Monitors, and a Master format at the top of that tab says what the main mix is - it drives the master meter, the fold-down and the default for anything added later, while every monitor keeps its own. The master track is widened when a format needs more channels than it has, and never narrowed again, since those channels may be carrying something the Control Room knows nothing about
--   + Control Room: Fixed multichannel hardware outputs being described wrongly. REAPER packs the send width above the channel offset in I_SRCCHAN, so a 6 channel send arrives as 3072 plus the offset, and only the mono bit was being read out of it - which showed every 5.1 send as "Mono" and every quad one as "Stereo". Anyone who had built a multichannel output in REAPER's own routing dialog was reading the wrong thing about it
--   + Control Room: Monitor modes follow the format. Full plays the whole bed, Mono Sum collapses it, and each speaker can be soloed by name - L, R, C, LFE, Ls, Rs - to check one driver at a time. L Speaker and R Speaker stay for stereo monitors, where panning is the thing that makes sense. The old Stereo, L Source and R Source modes map onto the new ones, so existing setups carry over unchanged
--   + Control Room: Fold to Stereo, a new monitor mode for hearing what a surround mix collapses to. REAPER's master cannot send to a regular track and an FX on the master would colour every output, so the downmix (new TK Control Room Downmix JSFX) writes a stereo pair into spare master channels past the bed and the monitor reads that instead - the surround feed to the main outputs is left alone. Centre and surround levels are adjustable, LFE is left out by default as most delivery specs ask, and its level reaches +10 dB for when you do want it at the gain a surround listener hears it at
--   + Control Room: Switching the last monitor away from Fold to Stereo stops the downmix instead of deleting it, so it can no longer sit there overwriting the fold pair while nothing listens. Setup shows "(idle)" when that has happened, and the Remove button beside it takes the plugin out properly
--   + Control Room: The meter draws a bar per channel with the speaker names on the peaks, and the loudness numbers under it are measured to ITU-R BS.1770-4 for surround - front channels at unity, surround and back channels at 1.41, LFE out of the loudness sum but still in the true peak. The meter JSFX carries eight pins for it; on a stereo master the rest are silent, so a stereo reading is exactly what it always was
--   + Control Room: A monitor's format is remembered rather than read back from its send, because soloing a speaker rewrites that send to a single channel and destroys the evidence of which group it came from. Without it, picking "C Only" once would have left the monitor mono for good
--   + Control Room: Cue outputs take the same formats and widen their own track when they need to, and the Targets tab lists the destinations available at a chosen width instead of assuming pairs
-- v0.6.65
--   + Plugin Browser, Instrument Rack and Instrument Console now show the custom images you assign in the TK FX Browser (right-click a plugin there > "Set Custom Image...") instead of the captured screenshot, so JSFX and other plugins that don't capture well can carry their own artwork everywhere
-- v0.6.64
--   + XY Pad: An assignment can now run inverted and cover a stretch of its target rather than all of it, set with an Invert switch and a Min and Max slider in the new "Travel" part of the right-click menu. It sits between the pad and the target rather than inside any one kind of it, so it works the same for an FX parameter, a volume, a pan or a send, and it applies to the recorded automation as well. Setting Min above Max is a second way of running it backwards. The row shows what is set as [INV 20-60%] against its right edge, out of reach of the truncation a long name goes through, and assigning something new clears the travel while leaving the slot's scaling and curve alone
--   + XY Pad: The assignment rows now carry the live value of their target, so the pad can be ridden without the plugin window open. In corner mode the number in each corner is the value read back from the target instead of that corner's share of the blend - not the same thing once a curve, a travel or a level law sits in between, where a corner on a quarter of the puck can be a parameter at 40%. The share is what the corner's tint says, which is the better thing to show it with anyway
--   + XY Pad: In corner mode a corner can name the track it points at, since "Volume" or "Pan" on its own is too little to go on. A Names button cycles off, Auto and Always; Auto shows the name only when the four corners are not all on the same track, or when the target is a volume or a pan, and it is dropped again when the corner is too small to give three lines the room
--   + Instrument Rack: The invert and the range of a macro assignment were there but buried - the range only as "Set Current As Min/Max", with nothing anywhere to say it was in force. The assignment row now carries the same [INV 20-60%] badge, and its submenu a readout, a Min and a Max slider and a Reset Range next to the two existing actions
--   + Instrument Rack: Fixed the macro assignment submenu closing the moment a range was changed. That badge is part of the menu label and ImGui hashes the whole label into the widget id, so every percentage handed the open submenu a new identity. Invert is a checkbox now rather than a menu item, and the three range actions no longer close the menu either, so a min and a max can be set in one go
-- v0.6.63
--   + Instrument Rack: "Replace FX..." can now go through REAPER's own FX browser instead of the Quick Add list, picked with a new "Replace FX target" in the settings menu next to the existing "Add FX target". REAPER's browser reports nothing back, so the plugin you add there is spotted on the track, taken back out again and put through the same replace path as before - the slot, the container, an input or take FX chain and the parallel flag all stay as they were. The FX chain window that REAPER opens on adding is closed again if it was not already open
--   + XY Pad: A four-way send morph no longer dips in the middle. The four corner weights always add up to 1, so the centre hands each corner a quarter - and that quarter used to be laid out linearly over the fader's dB range, which puts every send at -42 dB with the level collapsing towards the middle and jumping back up at the edges. The fraction is now a gain, so the four sum back to roughly the level a single corner gives: Equal power (the new default, gain = sqrt, centre -6 dB) for unrelated material, or Linear (gain = the weight, centre -12 dB) which is exactly constant when the four sends carry the same signal
--   + XY Pad: The scaling is a choice, kept per slot rather than per module, since four corners can hold four different kinds of target: Equal power, Linear, or Fader (dB) for the old behaviour, which still suits a single volume ridden over one axis. It sits in the right-click menu of the assignment row, with "Use this scaling for every slot" to set all four at once, and the pick doubles as the default for whatever is assigned next
--   + XY Pad: Under Equal power and Linear a target at the top of its travel is unity, so a morph can never boost. A Max gain slider (0 to +12 dB) in the same menu lifts that ceiling for anyone who wants headroom
--   + XY Pad: In corner mode each corner now shows the dB it is actually at for a volume or send target, rather than its share of the blend - 25% says nothing about how loud that corner is. FX parameters still show their percentage
--   + XY Pad: Added a response curve per slot for FX parameters (Linear, Log, Log +, Exp, Exp +), for the plugins whose 0..1 does not feel right - a frequency spread linearly over 20 Hz to 20 kHz being the classic. It is off by default and has to be picked by hand: a plugin parameter arrives with its own taper already in it, and REAPER exposes no taper type to detect, so guessing one would be exactly that. The curve applies to the recorded automation as well
--   + XY Pad: A pan target offers neither, on purpose. A level scaling is about turning a position into a gain and about four gains keeping their loudness together; pan is not a gain but a position between left and right, and that is linear by definition - the middle of the pad is the middle of the pan field. REAPER's own pan law (-3 dB, -6 dB and so on) is compensation applied after the value we set, per project or per track, so laying anything on top of it here would double up and no longer match what the mixer shows
--   + XY Pad: The value readout, the tooltips and the status line follow the scaling in force, so the dB shown is the dB the fader is at; the tooltip of an assignment row names its scaling or curve
-- v0.6.62
--   + XY Pad: Besides FX parameters an axis or corner can now drive a track's volume, its pan or one of its send levels - four sends on the four corners is a real four-way blend. Those have no equivalent of the Learn button, since REAPER remembers no last-touched track control, so they are picked with a right-click on the assignment row from whichever track is selected. Setting up a send morph is one action: "Morph the first 4 sends onto the corners" fills all four at once and switches the pad to corner mode, rather than four right-clicks and remembering which send went where. Levels run over a dB range rather than REAPER's raw volume scale, and the readout shows dB or a pan position accordingly. Existing FX assignments are read exactly as before
--   + XY Pad: Automation recording covers the track targets too. Volume and send levels are written through fader scaling and pan in its own range, so the points land where REAPER expects them. A missing volume or pan envelope is brought into view automatically, restoring the track selection afterwards since that action reads it, and the command id is checked against the action's name before being fired. A send envelope still has to be shown by hand - no action targets one particular send - and the status line says so rather than silently writing nothing
--   + XY Pad: Recording and listening back each need two things set the opposite way round - the envelope out of the way and the track writing to record, the envelope playing and the track not writing to hear it - and getting one wrong overwrites the take you just made. One button now owns both: Free (the pad moves, nothing recorded or played), Record (pad free, automation written) and Play (the take plays back, the pad stands back), cycled with a click and lit red while recording. It shares one row of three equal buttons with the two pad modes; the individual automation modes, the global override and clearing the recorded points sit in its right-click menu
--   + XY Pad: An automation button sits right-aligned beside the mode tabs, showing the mode actually in force and lighting up when it is one that records. It sets Trim/Read, Read, Touch, Write or Latch on every track the pad writes to - in corner mode those four parameters can sit on four different tracks, so all of them are armed at once - and the same menu drives the global override, marked with a G on the button while one is in force
--   + XY Pad: Movements now land in automation. Setting a parameter through the API moves it without going past REAPER's automation writer, so points are written here instead - while the transport rolls and only for tracks in touch, write or latch (or under a global override), so a track in read or trim never gets an envelope it did not ask for. Points are thinned like the movements themselves and sorted once when the transport stops, and the status line says "writing automation" while it happens. Works the same for a drag, a movement and a MIDI trigger, since all three go through one place
--   + XY Pad: Plugin names are shown clean - "VST3: Diva (u-he)" becomes "Diva" - by dropping the format tag and the trailing vendor and channel-count brackets. The tag is matched against a known list rather than everything up to a colon, so a plugin genuinely called "Delay: Tape" keeps its name, and the tooltip still shows the full one
--   + XY Pad: Fixed the plugin and parameter names showing as "FX 0" and "Param 3" - those REAPER calls hand back a success flag first and the text second, and only the flag was being read. The formatted value in the tooltip was falling back to a bare percentage for the same reason
--   + XY Pad: Hovering an assignment row spells it out in full - track, plugin, parameter and its current value - since that row is exactly what gets truncated when the module is narrow
--   + XY Pad: The assignment rows are stacked tighter, which matters most in the four corner mode where there are twice as many of them - the space saved goes to the pad
--   + XY Pad: A 4 corners mode next to the 2 axes one - a parameter per corner, blended by how near the puck is, with the four weights always adding up to 1. Sit in a corner and that parameter is full while the rest are at zero, sit in the middle and everyone gets a quarter, which is what makes it a proper morph between four sends or four settings
--   + XY Pad: Each corner glows in the colour of the track its parameter lives on, at the strength of that corner's share, with the parameter name and its percentage in the corner itself - so the blend is something you see rather than a number you read
--   + XY Pad: Corner assignments are stored beside the axis ones instead of replacing them, so switching modes leaves both set-ups intact, and a movement records the puck rather than the parameter values - existing movements therefore play back in either mode
-- v0.6.61
--   + XY Pad: Added the missing "TK Workbench: Open XY Pad" action, so the module can be opened straight from REAPER's action list or a toolbar button like every other one
--   + XY Pad: The pad now shrinks with the window (down to a floor) instead of pushing the readout, the movements and the trigger row out of sight, and the spacing between rows was tightened to give the pad itself more of the height
-- v0.6.60
--   + New module: XY Pad - drag one puck to move two FX parameters at once, for quick two-handed tweaking without hunting through an FX window. Press Learn after touching a parameter to bind it to X or Y (track FX, including record FX); the puck follows the parameters, so moves made elsewhere show up too, and the readout under the pad uses the plugin's own formatting. Momentary mode puts both parameters back where they were when you let go, so you can ride a filter and drop it. Assignments are stored per project and keep pointing at the right track after a reorder
--   + XY Pad: Movement recording - press Record, get a count-in in beats, then everything the two parameters do is captured and saved as a movement you can replay, loop and delete. The clock only starts on your first actual move, so a count-in you spend thinking costs nothing, and the still tail between letting go and reaching Stop is trimmed off again. Recording samples the parameters rather than the mouse, so a move made in the FX window or from a control surface is caught too, and repeated points are thinned out so a long gesture stays a few kilobytes. Playback scales to the project tempo using the tempo it was recorded at, and both recording and playback keep running while you are in another module. Movements are stored globally and survive a REAPER restart, so they can be reused across projects, and a right-click offers rename and delete
--   + XY Pad: MIDI triggered movements - a note on the modulated track's own input starts the armed movement (the one you last clicked), filtered by the device and channel that track is set to. Note mode plays it once, or loops it if Loop is on; Gate mode loops it while a note is held and stops on the last note off; Hold mode does the same but freezes the movement where it was instead of stopping, so the next note carries on from there rather than starting over. Retrigger restarts from the beginning on every note or lets the movement run on. Polling is one API call and one integer compare per idle frame, so nothing is paid for until a note actually arrives
--   + New block: Transport - Info: a readout of whatever you are working on, as label / value rows. Project shows name, length, tempo and meter, sample rate, track and item counts, markers and regions, and the cursor; Track shows number and name, item count, volume, pan, channels, FX count and its mute/solo/arm state; Item shows take name (with which take of how many), position, length and end, source file with its rate and channels or the note and CC count for MIDI, play rate and pitch when altered, and fade lengths; Region shows number, name, bounds, length and colour
--   + Transport: Info - in Auto the context follows whatever you selected last rather than a fixed order, so picking a region while an item is still selected shows the region; the Prj / Trk / Item / Rgn chips pin one by hand
--   + Transport: Info - every context reserves the same height, so switching one does not shift the cards below it, and hovering the rows gives the full values untruncated
--   + New block: Transport - Levels: master, monitor and the selected track on one card, each with a fader, a mute and (for the track) a solo. Monitor means the same thing it does in Control Room - the master's first hardware output send, so the level going to the speakers - and the row dims to "--" when the master feeds nothing. The track row follows the selection and carries the track number, name and colour
--   + Transport: Levels - the faders run in dB rather than on REAPER's 0..4 volume scale, where unity would sit at a quarter of the travel; double-click a fader for unity, and the solo column stays reserved on every row so the faders line up
--   + Transport: Each card now carries its name in its drag strip, small and dim next to the grip dots, so a tall stack stays readable at a glance - left-aligned rather than centred, so scanning follows one fixed edge instead of a centre that moves with every name length. Costs a few pixels of strip height, so there is a "Show block names on the cards" switch in the Blocks menu to turn it off
-- v0.6.50
--   + New block: Transport - Markers & regions: every marker and region as a colour-coded chip, wrapped over as many rows as fit and scrollable beyond that; markers show a flag and regions a bar, and the one your cursor sits in lights up (during playback it follows the play cursor)
--   + Transport: Markers & regions - click a marker to move the edit cursor, click a region to also set the time selection, double-click to play from there or to loop and play a region, right-click for rename, go to, set time selection, loop and play, or delete
--   + Transport: Markers & regions - toolbar with prev/next marker, an M+R / M / R filter that cycles on click, +M (marker at the edit cursor) and +R (region from the time selection), plus a line naming the marker or region you are currently in
--   + Transport: Markers & regions - right-click a chip to colour the marker or region straight from Color Studio's active palette, pick any colour with the custom picker, grab Color Studio's active colour, or reset to REAPER's default; dragging the picker previews live and lands as a single undo point
--   + Transport: Markers & regions - a ruler lanes button next to +M / +R that hides or shows every ruler lane in one click. REAPER's per-lane actions only toggle and report no state, so this sets the lanes directly through the project's own lane info instead: always all hidden or all shown, never a mix, empty lanes included
--   + New block: Transport - Record status: the take counter big in view with a red dot that blinks while recording, an ARM badge, free space on the recording path with an estimate of how long that lasts at the current arm count (turns amber under ten minutes), and a list of the armed tracks in their track colour - click one to select and scroll to it, right-click to disarm, and cycle its input monitoring (off / on / tape style) with the chip on the right
--   + Transport: Record status - the take counter runs on timeline time, so it matches the length of the item you end up with rather than the wall clock. After you stop it holds the last take's length (the dot goes grey) until the next recording starts, so undoing or deleting that take does not clear it. The remaining-time estimate assumes 24-bit, so recording in 32-bit float leaves you roughly a quarter less than shown
--   + New block: Transport - Pre-roll / count-in: pre-roll on play and on record with its length in measures, count-in on play and on record, and the record mode (normal / time selection auto-punch / selected item auto-punch) as three chips where the active one lights up, plus a gear to REAPER's own metronome and pre-roll settings - all of it a click away instead of buried in a dialog
--   + Transport: Metronome - the click pattern as a row of beat cells instead of a grid in a dialog: one cell per beat carrying the click sound it uses (A to D) or a dash when muted, click to cycle through them. Odd meters simply get more cells, and while the transport rolls the row follows the play cursor so the meter you hear is the meter you see
--   + Transport: Metronome - the row reads and writes the pattern of the tempo / time signature marker governing the cursor, so editing inside a 5/4 section changes that marker's own pattern instead of scattering new markers through the tempo map. The time signature at the right of the row says which pattern you are looking at: dim for the project's own, accent-coloured when a marker carries one of its own - REAPER's metronome settings only ever show the project pattern, so the two can differ
--   + Transport: Metronome - a click pattern REAPER will not take is rolled back and every edit is a single undo step, so changing the pattern cannot leave the project without an audible click
--   + Transport: Transport buttons - two curved back / forward arrows that step through the edit cursor's history, so a quick look at the end of the project is one click away from where you were. Only deliberate jumps are kept, so dragging or nudging the cursor never floods the list, and the history keeps filling up while another module is on screen
--   + Transport: The Transport buttons card is now pinned to the anchored edge (top or bottom) instead of scrolling along with the rest, so the transport stays in view however short the window gets; the other cards scroll behind it once they no longer fit. The pinned card has no drag handle and shows as "Pinned" in the Blocks menu
--   + Transport: Time selection - A / B / C section slots with a Loop toggle next to them: right-click stores the current time selection, left-click recalls it. Recalling sets the time selection and loop points and seeks, so with repeat on you drop straight into the other section while mixing; slots are stored per project and the slot matching the current selection lights up
--   + Transport: Navigator card - four zoom buttons along the right edge: P zooms out to the whole project (time and track heights), and slots 1-3 store a zoom - right-click to save, left-click to recall - kept per project including track heights and vertical scroll
--   + Color Studio: Exposes its active palette to other modules (including the brightness/saturation adjustment, colour count, sorting and custom palettes), so the Transport marker strip always offers exactly the colours Color Studio is showing
--   + Fixed: "ImGui_EndChild: Missing PopID()" crashes that took the whole window down - Project Browser (list, detail and preview panels), Script Launcher, Arrange BG Presets and FX Chain Builder all called EndChild outside the "if BeginChild succeeded" block, so a panel clipped out of view (in split view, or scrolled off-screen) ended a child that was never begun
--   + Fixed: Workbench - a failing frame no longer takes the whole window down. An ImGui structural failure in a module invalidates the context, after which every remaining call in that frame fails as well, ending the defer chain; the frame is now caught and simply dropped, and the next one starts from a fresh context
--   + Fixed: Workbench - a module error is no longer drawn on an ImGui context that the failure just invalidated, which raised a second, confusing error on top of the real one and hid it
--   + Fixed: Project Browser - the Previews popup and its rows are guarded so a failure inside them cannot skip an EndPopup or PopID, and the preview panel's error is written to the log instead of being swallowed silently
-- v0.6.49
--   + Script Launcher: Added a List view mode next to tiles, with click-to-run items and Edit/Delete on right-click
--   + Script Launcher: Labels toggle now also works in List view by grouping entries under label headers
--   + Script Launcher: Search field layout tightened to use remaining toolbar width with less empty right-side space
--   + Workbench: Right-click the Split view button to toggle split on/off directly (left-click still opens the split menu)
--   + Workbench: Split view button tooltip now mentions the new right-click toggle
--   + Transport: Header Blocks button spacing tightened for a cleaner right-aligned look
-- v0.6.48
--   + Send Studio: Added Link mode to mirror matching sends across selected tracks (relative volume/pan, absolute mute/mode/phase/mono), with a toolbar Link toggle and status feedback while adjusting
--   + Send Studio: In list view, the live volume and pan slider value is now drawn above the handle while hovering/dragging, so the mouse cursor no longer covers it
--   + Send Studio: The Add Send/Receive picker can now be stretched taller by dragging the grip at its bottom edge; the height is remembered and can grow up to nearly the screen height
--   + Send Studio: The return track's volume and pan (in the lane's right-click menu) can be reset with a right-click on the slider or a small 0 / C button next to it
--   + Send Studio: The Pin button is now a compact thumbtack icon so track names get more room, and the track fader's + button now lines up right under it
-- v0.6.41
--   + Fixed: Module rail - tiles were pushed off-centre when the rail is docked on the left
--   + Fixed: Transport - right-clicking a tile to open a module in split view could throw an ImGui EndChild error
-- v0.6.4
--   + New module: Transport - a modular transport built from cards you can add, remove, drag to reorder, and anchor to the top or bottom of the window (via the Blocks button)
--   + Transport: Transport buttons card - vector-drawn go-to-start / play / pause / stop / record / go-to-end / loop that justify to the full card width, with live play/record/repeat state highlighting
--   + Transport: Tempo card - a large draggable/scrollable BPM readout (double-click to type), -/Tap/+ row, and a clickable time-signature badge to set the signature at the current measure or project start
--   + Transport: Time selection card - big length readout with a bars.beats badge, start/end, and buttons to move the edit cursor to the selection start/end or clear it
--   + Transport: Play rate card - themed slider (0.25-4x) with a 1x reset and a preserve-pitch toggle
--   + Transport: Metronome card - on/off, click volume, 0.5x/1x/2x/4x speed presets, metronome-during-playback/record toggles, and a gear that opens REAPER's metronome settings
--   + Transport: Navigator card - a 2D bird's-eye of the arrange (tracks x time) with items, markers/regions and the edit/play cursor; drag the viewport to pan, edges/wheel to zoom time, Ctrl+wheel to zoom track height, and zoom past the project end
--   + Transport: Master scope card - a scrolling peak view of the master output that runs during playback, scrolls out on stop, and restarts on the next play
--   + Workbench: Added an optional Module rail - a slim, always-visible strip of module icons along the left or right window edge (icon-only, name on hover) so any module is one click away; right-click a rail icon to load that module into the split view; toggle and side live in Preferences
-- v0.6.3
--   + Send Studio: The selected track's own volume fader now sits directly under the track name (the "Track" label is gone) and has a Solo button next to Mute
-- v0.6.2
--   + Send Studio: The header shows the track name in a bar tinted with the track colour that fills up to the Pin button (with the multi-select count shown inside it); long names are truncated so Pin always stays in view, and the module label was dropped
--   + Send Studio: Added prev/next arrows in the header to step through the project's tracks (cyclic), with Shift-click to jump to the first / last track
--   + Send Studio: Card view can now fill a column top-to-bottom before starting the next one (better for a tall, narrow side-docker), with a Cols/Rows toggle in the footer to switch back to the row-first layout
--   + Send Studio: The Add Send/Receive picker lets you star favourite destination tracks (stored per project) that float to the top of the list
--   + Send Studio: View and open the FX of a send/receive's track - an FX button (list) and FX submenu (right-click) that open the FX chain or any individual plugin
--   + Send Studio: Solo (S) isolates one send/receive by muting the track's other sends and receives - exclusive by default, Ctrl-click to add more; the solo state is stored per project so it survives reloads and is fully reversible; labelled Solo send / Solo receive to match the lane
--   + Send Studio: Solo defeat (D) exempts a send/receive so it stays audible whenever a solo is active on the track
--   + Send Studio: Listen (headphone) solos the original and return track and mutes the track's other routings so only that path plays; Shift-click listens to the return only (drops the source's master send for the wet return), with a distinct highlight colour per mode; the return track's own volume and pan are in the right-click / "..." menu
--   + Send Studio: Added MIDI source/destination channel selectors in the routing popup
--   + Send Studio: Reworked the strip buttons - Mute/Solo/Defeat on the top row and a drawn headphone Listen icon with Phase/Mono below - and trimmed the right-click menu to options that are not already on the strip
--   + Send Studio: The New Bus and Add Send/Receive track pickers are now modal windows, so a click inside them can no longer leak through to the panel behind (e.g. clicking Create no longer also triggers a strip control underneath)
--   + Send Studio: Selecting a send/receive's other track (clicking its name) now scrolls the mixer to that track too, matching the TCP behaviour
--   + Send Studio: The Add Send/Receive track picker is larger with a wider filter, so it is easier to browse and less prone to overscrolling
--   + Send Studio: The audio-channel routing popup now lists higher channel pairs (3/4, 5/6 ...) even when the track does not have them yet - picking one grows the track's channel count automatically (marked with "(add)")
--   + Send Studio: Added a Track fader row (the selected/pinned track's own volume and mute, with -1/+1 dB nudge), handy for aux/return tracks you keep at 0 and blend with the track fader
-- v0.6.1
--   + Send Studio: Fixed the mixer-strip faders (volume and pan) not responding on some setups - the strips now use ReaImGui's own hit-testing and input capture instead of raw mouse state, so dragging works regardless of ReaImGui version, window focus or docking
--   + Send Studio: Fixed the Listen (L) button not isolating properly - it now uses Solo In Place, so soloing the return bus no longer un-mutes every other track that feeds it; you hear only the original track and its return
--   + Send Studio: The list view no longer runs off-screen in a narrow side-docker - the track name fills the top line and the controls flow onto the next line(s) when there is not enough width, with a divider between sends; Shift+wheel over the list volume/pan sliders does the same fine-adjust as the card faders
--   + Send Studio: Added -1 dB / +1 dB nudge buttons around the volume of each send (either side of the readout on card strips, next to the slider in list view), for quick step adjustments without dragging
--   + Send Studio: In list view the volume/pan value stays readable when the slider handle passes over it (the grab now uses the muted accent colour that contrasts with the text)
-- v0.6.0
--   + Send Studio: New module for fast send/receive management, styled after the Control Room module - a vertical mixer-strip (card) view that flexes to fill the window up to a maximum width and wraps to the next row when it gets too narrow, plus a compact list view; toggle between them in the footer
--   + Send Studio: Per send/receive controls for volume (drag fader, Shift+scroll for fine, double-click for 0 dB), pan, mute, phase invert, mono sum, send mode (Post / Pre-FX / Pre-Fader) and the source/destination audio channel; right-click a strip for the same options plus "select destination track" and remove
--   + Send Studio: Solo send (S) isolates one send among the sends to the same track, and Listen (L) auditions "return and original tracks only" by soloing just the source and destination track; a "Reset Solo" button appears while either is active and restores the previous state, so you never leave the project soloed by accident
--   + Send Studio: Pinnable target track (follow the selection or lock onto one track) and multi-track creation - with several tracks selected, Add / New bus / Paste apply to all of them at once
--   + Send Studio: Add sends/receives via a filterable track picker, create a new bus track and send the active track(s) to it in one action, and copy/paste a track's sends (including channels, mode, phase, mono and pan) onto other tracks
-- v0.5.11
--   + Media Browser: Fixed embedded cover art on Opus/OGG (and other Vorbis-tagged) files being decoded corruptly - the Base64 decoder for METADATA_BLOCK_PICTURE artwork kept growing its bit accumulator without discarding already-emitted bits, which mangled larger images and caused "Corrupt JPEG data: N extraneous bytes before marker" errors plus unreadable cached thumbnails; this replaces the 0.5.10 workaround with the real fix and the cover cache is regenerated automatically so thumbnails now load correctly (thanks to the forum user who tracked down the root cause)
-- v0.5.10
--   + Media Browser: Fixed the ReaScript console being spammed with "Corrupt JPEG data: N extraneous bytes before marker" warnings when opening folders with Opus/OGG (or other) files whose embedded JPEG cover art is slightly non-standard; the artwork is now sanitized (stray bytes between JPEG header segments are stripped, image data kept untouched) before it is cached, and already-cached covers are cleaned up automatically on first view, so the thumbnails still show without the console noise
-- v0.5.9
--   + Timepiece: Added a Recording alert that makes the panel unmistakable while REAPER is recording - a thick red border, a blinking REC dot and a red clock, plus a pulsing red background, so you can tell from across the room that it is definitely recording (on by default)
--   + Timepiece: Added a separate "pulse background" toggle so you can keep the red border, REC dot and red clock while turning off the pulsing red panel for a calmer alert
-- v0.5.8
--   + Notes: per-selection text sizing - select text and use Increase/Decrease Text Size (right-click menu or Ctrl+Shift+. / Ctrl+Shift+,) to resize just the selected part, independent from the block font size; larger text is baseline-aligned and works together with bold
--   + Notes: In Auto mode a clicked region/marker now takes priority when it is the most recently changed selection, so clicking a region shows its note even while a track or item stays selected; when the region is not the freshest pick it falls back to Item > Track > Region > Project, and deselecting the item (which REAPER does when you click a region) no longer briefly snaps to the track note first
--   + Notes: In the dedicated Marker/Region scope markers are now click-only (click a marker to view its note) while regions follow the edit cursor automatically - move the cursor into a region and its note shows without clicking, even when another region is still selected
--   + Notes: During playback the note now follows the region under the play cursor automatically, in both Auto mode and the dedicated Region scope, so region notes advance with the playhead (a region has duration and wins over a leftover selected marker while playing); when playback stops everything falls back to the selection-driven behavior
-- v0.5.7
--   + Notes: Track notes are now stored on the track itself, so they travel with track templates and copied tracks and reappear automatically when such a track is loaded into another project (multi-block notes and formatting included)
--   + Notes: Added an optional Track note indicator (Notes settings, off by default) that appends a small configurable marker (default bullet) after the name of every track that has a note, so you can spot them at a glance in the TCP/MCP; the marker travels with templates too and is placed after the name so scripts that parse the start of the track name keep working
--   + Notes: Added a Marker/Region scope alongside Global/Project/Track/Item - in Auto mode a selected (clicked) region or marker now takes priority over Project notes (after Item and Track), and the dedicated Region scope also follows the region/last marker at the edit cursor (or the play cursor during playback); notes are stored per region/marker number and inherit the region/marker color
--   + Instrument Rack: Right-clicking an FX tile screenshot now opens the same menu as the three-dots (...) button (Bypass, Parallel, Wrap in container, Remove, etc.), in both orientations and for track, input and item FX
--   + Workbench: The main floating window no longer steals keyboard focus from REAPER when it (re)appears, so transport and other shortcuts keep working; the window only takes focus when you click in it
-- v0.5.6
--   + Media Browser / Action Clipboard: TK Workbench now shows an in-app warning window listing any missing native extensions (TK Native Helper, TK Action Capture) instead of only printing to the console
-- v0.5.5
--   + Media Browser: Added drag-and-drop of samples straight onto external plugin windows (ReaSamplOmatic5000, Cartridge, Speedrum, etc.) via the new TK Native Helper extension; dragging onto a track still inserts as before
-- v0.5.4
--   + Instrument Rack: Dropping plugins from a TK FX Browser now works regardless of window open order, and multiple browsers can be open at once
--   + Instrument Rack: Added TCP/MCP support for pinned parameters - right-click a pinned parameter to "Add to TCP/MCP" or "Remove from TCP/MCP", plus a settings option to automatically add every new pin to the TCP/MCP
--   + Instrument Rack: Add to TCP/MCP is disabled for parameters of plugins inside a container (the native API does not support this), with a tooltip explaining why
--   + Instrument Rack: Added a per-FX "Sync this FX's TCP/MCP params to pins" option in the FX tile menu that pins any parameter already visible in the TCP/MCP
--   + Instrument Rack: Added FX A/B - a per-FX A/B button at the front of the FX tile toolbar to capture and toggle between two parameter snapshots (right-click to copy the current state to A or B, or reset)
-- v0.5.3
--   + Instrument Rack: Added a "Text alpha" slider to fade the pinned parameter value/label text independently of the knob/button transparency
--   + Instrument Rack: Fixed pinned parameters not being horizontally centered in the FX tile (they leaned slightly to the left)
--   + Instrument Rack: Fixed the per-parameter "Label under: Hide" setting not surviving a restart
--   + Instrument Rack: Fixed double-click reset on button/cycle parameters cycling the value instead of resetting; added a right-click "Save current value as reset default" so double-click can restore a chosen value
--   + Instrument Rack: Pinned parameters with a multi-value cycle button now show a progress bar that advances per step, so the button stays lit and indicates its position
--   + Instrument Rack: Fixed pinning the last touched parameter when the plugin lives inside a container (now uses GetTouchedOrFocusedFX)
--   + Instrument Rack: Pinned parameters with a hidden value now reveal the value while you hover over them
--   + Instrument Rack: Added a "Show shortcut hints in tooltips" option to hide the extra control hints in parameter tooltips while always keeping the name and value
--   + Instrument Rack: Fixed default plugin pins being lost after restarting REAPER (only the first plugin's pins survived); saved pins now persist reliably and existing saves are migrated automatically
--   + FX Groups: Parameters of FX nested inside containers can now be linked across group members (containers are traversed depth-first, including nested containers)
--   + Instrument Rack: Added a "Hide track number" option that hides the track number and separator in the rack header, showing only the track name (both orientations)
--   + Instrument Rack: Added "Track name opacity" and "Panel name opacity" sliders to fade the track name and the section/panel names (Track FX, Input FX, Item FX)
--   + Media Browser: Added embedded cover art support for Opus and OGG files (reads METADATA_BLOCK_PICTURE from VorbisComment tags)
--   + Media Browser: Audio files without embedded cover art now fall back to the folder cover (cover/folder/front image) before the type badge
--   + Media Browser: Added a "Show cover art" right-click option that opens a resizable square viewer window (embedded art, folder cover fallback, else no image); the image follows the selected file and the window has a themed red close button and scroll-to-resize
--   + Media Browser: The cover art viewer now remembers its last position and size between sessions
--   + Instrument Rack: Fixed a crash ("ImGui_EndChild: Missing PopID()") in the horizontal rack when a collapsed FX tile or the vertical title bar was scrolled off-screen (EndChild is now only called when BeginChild succeeded)
--   + Instrument Rack (Horizontal): The standalone launcher now logs draw errors to the ReaScript console and keeps running instead of dying on a secondary invalid-context error
--   + Lyrics: Added a "Line spacing" setting to control the vertical space between lyric lines
--   + Lyrics: Right-click the lyrics area to copy the full lyrics text to the clipboard
-- v0.5.2
--   + Lyrics: Added a new module that shows a playback timer and synced lyrics for the playing audio item
--   + Lyrics: Reads embedded lyrics straight from the MP3 ID3 tag (USLT and synced SYLT), with .lrc file and track notes as fallback
--   + Lyrics: foobar2000-style centered layout with the timestamp above each line, word wrap, and an enlarged active line
--   + Lyrics: Synced highlight and autoscroll follow playback, with the active line scrolled into view
--   + Lyrics: Click a line to seek to that moment, with an adjustable sync offset (ms) and active line scale
--   + Lyrics: Settings for source mode, font size, and toggles for name, timer, progress bar, timestamps, autoscroll, and click-to-seek
--   + Workbench: Added a mappable module action for opening Lyrics
--   + Workbench: Fixed an "ImGui_End: Calling End() too many times!" crash that could occur on startup or with docked/small windows by only ending child panels when they are visible
--   + FX Groups: Fixed the module failing to load ("fx_groups load error") for ReaPack users by including the missing core/quick_fx_menu.lua dependency in the package
--   + Media Browser: Audio files now show embedded cover art (MP3 ID3v2 APIC, FLAC PICTURE, M4A/MP4 covr) as a thumbnail, with folder art and the type badge as fallback
--   + Instrument Rack: Added a "Show border around Add buttons" option to remove the outline/circle around the Add FX and Quick Add buttons (border still shown on hover and while dragging)
--   + Instrument Rack: Added a "Hide button value until used" option that hides the value on button / cycle parameters until you click or drag them (like the knob layout)
--   + Instrument Rack: Hold Shift while dragging a knob or button parameter for fine adjustment
--   + Instrument Rack: Default pinned parameters now also apply to offline FX, reliably persist across REAPER restarts, and keep their custom parameter names
-- v0.5.1
--   + Instrument Rack: Pinned parameters with discrete steps (e.g. modes) can now be shown as a click-to-cycle button that steps through each value, with drag to scrub and double-click to reset
--   + Instrument Rack: Stepped values are detected even when a plugin does not report step sizes, by briefly scanning the parameter's value labels
--   + Instrument Rack: Button-style pinned parameters automatically pick a stepped value cycle or an on/off button, and the cycle only appears when Button layout is selected
--   + Instrument Rack: Removed the border around pinned parameter buttons and made them slightly wider for easier reading
--   + Instrument Rack: Long values inside pinned parameter buttons are now truncated to fit the button width
--   + Instrument Rack: Added a per-parameter right-click option to show the name or value, and to show or hide the label under the knob/button, with a matching global default
--   + Instrument Rack: Added options to center the track name with an optional badge background, and to center the plugin name in FX tiles
--   + Instrument Rack: Horizontal FX tiles now widen automatically for 6-column parameter layouts so parameter spacing stays even
--   + Instrument Rack: Settings window now uses a two-column layout in horizontal orientation for a more compact view
--   + Instrument Rack: Removed the "Show value overlay while dragging" option
--   + Instrument Rack: Fixed per-parameter name/value and label-under choices not being saved with the project
--   + Instrument Rack: Add FX and Quick Add buttons now stay clearly visible in every theme, even when not hovered
--   + Instrument Rack: Quick Add now shows AU and AU instrument plugins under All Plugins
--   + Instrument Rack: Quick Add folders are now sorted naturally so numbered folders appear in order (1, 2, 3, ... 15) instead of scrambled
--   + Instrument Rack: Added a track color saturation slider to tone down inherited track colors
--   + Instrument Rack: Settings window now uses a two-column layout in vertical orientation as well, for a more compact view
--   + Instrument Rack: Fixed the horizontal (tilt) scroll wheel not scrolling the horizontal rack
-- v0.5.0
--   + FX Groups: Added a new module to link FX parameters across multiple tracks with a live, per-FX sync engine
--   + FX Groups: Manage groups in a compact, collapsible list with inline rename (double-click), color swatch, active toggle, and track management
--   + FX Groups: Link or unlink individual FX and parameters, with a per-FX SYNC button and selectable source track
--   + FX Groups: Add an FX to every track in a group at once via the cascading Quick Add menu
--   + Instrument Rack: Added response curves to macro parameter mappings with Power, S-Curve, Quantize, and Bipolar curve types
--   + Instrument Rack: Added a draggable graphical curve preview per mapping that reflects the selected curve type and invert state live
--   + Instrument Rack: Drag the curve pad up or down to change the curve amount and double-click to reset it to linear
--   + Instrument Rack: Curve type and amount are stored per mapping and persist with the project, defaulting to a linear Power curve for older projects
--   + Instrument Rack: Added a Highlight instruments option to visually distinguish instrument plugins in the rack
--   + Instrument Rack: Added a Plugin type badge on screenshot option showing a color-coded VST3, VST, CLAP, JS, AU, or LV2 badge per FX tile
--   + Instrument Rack: Added a Wet knob on FX containers (including nested containers) in both the vertical and horizontal rack, with drag to adjust and double/right-click to reset
--   + Instrument Rack: Container add zones now show the same Add FX and Quick Add buttons as the regular add zone, in both the vertical and horizontal rack
--   + Instrument Rack: Matched the container add and Quick Add button sizing to the regular add zone for a consistent look
--   + Home: Added an Instrument Rack (H) tile and module dropdown entry to quickly open the horizontal Instrument Rack
--   + Instrument Rack: Added an optional vertical title bar on the left of the horizontal rack, with the track number in a darker box on top, the truncated track name stacked below, and the pin, settings, and close buttons
--   + Instrument Rack: Tightened the spacing between collapsed section headers in the horizontal rack
-- v0.4.5
--   + Instrument Rack: Added a Quick Add cascading FX menu with Favorites, Recent, All Plugins (grouped by type), Category, Developer, Folders, FXChains and Container
-- v0.4.4
--   + Calculator: Added an option in Delay / Reverb to subtract pre-delay from decay/RT60 values, including selectable pre-delay source
--   + Instrument Rack: Fixed horizontal section collapse headers so text stays inside the header when tiles are compact or screenshots are hidden
--   + Instrument Rack: Simplified horizontal section labels to TRACK, INPUT, and TAKE
-- v0.4.3
--   + Instrument Rack: Added an option to hide parallel/serial signal flow badges in both vertical and horizontal layouts
--   + Instrument Rack: Horizontal header now includes a close dot next to the settings (...) button
--   + Instrument Rack: Refined vertical and horizontal spacing for section gaps, add zones, and flow badge placement
--   + Instrument Rack: Input FX section now supports the same flow badges/tree behavior as track FX
--   + Instrument Rack: Take FX tiles now keep parameter-slot space visible for consistent tile height
--   + Instrument Rack: Added Wet knob size and alpha controls, capped Wet knob size to 1.0, and adjusted Wet knob colors to a more neutral style
-- v0.4.2
--   + Preferences: Reorganized into themed tabs (General, Modules, Theme) so all settings live in one window; clicking the settings dot now opens Preferences directly
--   + Preferences: Added a Modules tab to show or hide individual modules in both the home tiles and the module dropdown, with Show all / Hide all
-- v0.4.1
--   + Home: Fixed module icons drawing outside their shapes at non-100% UI scaling (e.g. Calculator buttons and Arrange BG grid no longer overflow)
-- v0.4.0
--   + Calculator: Added a new module with Delay, Gain, Note, and Samples tabs for studio calculations
--   + Calculator: Delay tab shows note times (straight/dotted/triplet) with click-to-copy and ms/Hz toggle, plus reverb pre-delay and decay references
--   + Calculator: Gain tab converts dB to linear/percent/power and back, with a pan law reference
--   + Calculator: Note tab converts notes to frequency/MIDI and frequency to the nearest note with cents detune, using a configurable A4 reference
--   + Calculator: Samples tab converts milliseconds to samples and back, with note lengths in samples, following project tempo and sample rate (manual override available)
--   + Workbench: Added a mappable module action for opening Calculator
-- v0.3.9
--   + Media Browser: Spacebar now plays/stops the preview and Enter/Return toggles play/pause (resumes from the pause position), matching REAPER's transport; both are ignored while typing in a field
-- v0.3.8
--   + Instrument Rack: Container drop zones now double as add buttons — click one to add an FX straight into that container via the linked TK FX Browser, TK FX Browser Mini, or the internal Plugin Browser, while drag-and-drop into the container keeps working
--   + Instrument Rack: Right-click a container drop zone for Add FX... and Add empty container inside actions
--   + Instrument Rack: Container drop zones now match the look of the regular add button in both the vertical and horizontal rack
--   + Instrument Rack: Fixed a crash in the horizontal rack when a container scrolled off-screen
--   + Instrument Rack: Added modifier-click shortcuts on the whole FX tile (vertical and horizontal rack) — Alt-click deletes the plugin without confirmation, Shift-click bypasses, and Ctrl+Shift-click toggles offline
--   + Instrument Rack: TK FX Browser, TK FX Browser Mini, and the Plugin Browser now route added FX to the Input or Take chain when adding from the rack's Input or Item FX sections
--   + Instrument Rack: Opening an already running external TK FX Browser or Mini now shows it instead of toggling its visibility off
--   + Instrument Rack: Input and Item FX sections now always show their add button so you can add or drop the first FX even when the chain is empty (vertical and horizontal rack)
--   + Instrument Rack: Pinned parameter knobs and the wet knob now keep their last known values when an FX is set offline instead of disappearing or resetting to 100%
--   + Instrument Rack: Pinned parameter knobs now dim uniformly when an FX is set offline or bypassed
--   + Instrument Rack: Each FX section (Track, Input, Take) in the vertical rack now has a collapsible header with a chevron, sharing the collapse state with the horizontal rack
--   + Instrument Rack: Removed the redundant track name shown beneath the Input and Item FX section headers in the vertical rack
--   + Instrument Rack: Replaced the wet button with a rotary wet knob on the left of each FX tile that is draggable straight away, shows the live percentage while dragging, and resets to 100% on double/right-click
--   + Instrument Rack: Collapsing an FX tile now keeps the wet knob, name, and controls visible and only hides the screenshot and pinned parameters
--   + Instrument Rack: Renamed the take FX source toggle to Show take FX (selected item) with a clearer tooltip
--   + Instrument Rack: Double-click a pinned parameter under the screenshot to reset it to its default value (also in the horizontal rack)
--   + Instrument Rack: Saving plugin default pins now also stores the current parameter values, with a Restore saved parameter values on apply option to recall them automatically
--   + Instrument Rack: Grouped the settings popup into labelled sections (Display, Controls, FX sources, Layout, Default parameter pins, Add FX target) with divider lines
--   + Instrument Rack: Section header colors now match the horizontal banner opacity instead of appearing brighter
--   + Instrument Rack: Horizontal rack now also scrolls with a physical horizontal scroll wheel or tilt wheel
-- v0.3.7
--   + Media Browser: Fixed the Add Location folder picker being restricted to Desktop/Users on some systems
--   + Media Browser: Hold Shift while dragging a file onto a track to drop it into a new fixed lane (auto-enables fixed lanes)
--   + Media Browser: Added Stop preview on insert/load option (right-click the sync button); preview stops automatically after inserting to arrange or loading into RS5K/Cartridge
-- v0.3.6
--   + Notes: Added a scrollbar on the right of the body editor when text/images exceed the visible area
--   + Notes: Added mouse wheel scrolling inside the body editor
--   + Notes: Typing/pasting is no longer limited to the window height; the editor scrolls instead
-- v0.3.5
--   + Instrument Rack: Horizontal rack now scrolls horizontally using the dominant mouse wheel axis
--   + Instrument Rack: Added an option to invert the horizontal wheel scroll direction
--   + Instrument Rack: Added a Signal flow order option to arrange sections as Input > Take > Track
--   + Instrument Rack: Horizontal rack now follows Workbench theme and UI scale changes live without a restart
--   + Instrument Rack: Added an option to color section headers by track color
--   + Instrument Rack: Added an item name overlay on item FX tiles with item color background and the item name in the info bar and tooltip
--   + Instrument Rack: Raised the screenshot height range up to 400 px
--   + Instrument Rack: Added per-plugin default parameter pins with save, apply, and clear actions plus an optional auto-apply on load
--   + Instrument Rack: Added a settings (...) button on FX tiles that opens the same menu as right-click
--   + Workbench: Added a Background opacity slider for the main floating window
--   + Workbench: Added a separate Module panel opacity slider for module backgrounds
--   + Workbench: Preferences window now auto-resizes to its content and keeps the close button aligned to the right edge
--   + Media Browser: Sync rate to project tempo now reads embedded file BPM (ACID, ID3, Vorbis, XMP) before falling back to length matching
--   + Arrange BG: Added a new module for managing arrange, track, grid, and divider theme colors as presets
--   + Arrange BG: Added preset apply, A/B toggle, per-preset track/grid scope, color picker, and standalone action script generation
--   + Arrange BG: Added Reset colors for live theme colors and Restore theme file from backup
--   + Arrange BG: Added Grid full alpha to unlock the full grid color range with a one-time theme file backup
--   + Arrange BG: Added favorite theme loader supporting .ReaperTheme and .ReaperThemeZip files
--   + Workbench: Added mappable module actions for opening Arrange BG, Timepiece, and Track Tags
-- v0.3.4
--   + Workbench: Added a side-by-side option for split view alongside the stacked layout
-- v0.3.3
--   + Instrument Rack: Added a horizontal Instrument Rack window that can be opened from the rack settings
--   + Instrument Rack: Added a selectable macro count of 8 or 16
--   + Instrument Rack: Tiles now collapse horizontally into a narrow strip in horizontal layout
-- v0.3.2
--   + Workbench: Added a clear (X) button to module search fields in Media Browser, Plugin Browser, Project Browser, Script Launcher, Track Tags, and Action Browser
--   + Media Browser: Raised the default file scan cap to 200000 and added a configurable Max files setting up to five million
-- v0.3.1
--   + Control Room: Restored master meter screen state across REAPER restarts
--   + Control Room: Added a focused meter view with Back, Reset, settings, removable info labels, and adaptive meter height
--   + Notes: Kept the custom body editor typing target active so REAPER global shortcuts do not intercept note input
-- v0.3.0
--   + Workbench: Added manual UI scaling presets for small touch screens through large high-resolution displays
--   + Workbench: Added automatic contrast correction for readable text on light and dark theme backgrounds
--   + Workbench modules: Scaled module controls, panels, lists, grids, cards, meters, previews, and editor layouts across the Workbench
--   + Workbench: Fixed the module selector preview label after simplifying the title header
-- v0.2.9
--   + Tags: Restored previous TCP/MCP visibility when clearing active tag filters instead of forcing all tracks visible
--   + Tags: Added Restore previous visibility alongside explicit Show all tracks
-- v0.2.8
--   + Workbench: Fixed ReaPack delivery for the Tags module by adding modules/track_tags.lua to the package index
-- v0.2.7
--   + Workbench: Added auto-collapse edge offset and close-delay preferences
--   + Workbench: Kept auto-collapse expanded while popups, dropdowns, or hovered popup windows are active
--   + Workbench: Added module error logging to workbench_errors.txt and improved module error status labels
--   + Workbench: Stopped stale draw errors from inactive modules from taking over the global status bar
--   + Tags: Hardened track GUID handling with persistent fallbacks and skipped tracks without stable GUIDs
--   + Tags: Improved portable install store path handling, color normalization, and compact pane height safety
-- v0.2.6
--   + Workbench: Added floating-window auto-collapse with REAPER edge pinning, a keep-expanded pin button, and a 1px transparent hover strip
--   + Workbench: Added auto-height modes for manual height, arrange height, REAPER window height, and arrange-to-window-bottom height
--   + Workbench: Improved auto-collapse positioning with native-to-ImGui coordinate conversion for scaling and multi-monitor setups
--   + Workbench: Disabled auto-collapse preferences while Workbench is docked to clarify that auto-collapse is floating-only
--   + Plugin Browser: Fixed external FX drag overlay positioning on secondary monitors
--   + Plugin Browser: Kept Workbench expanded during pending and active external FX drags to prevent interrupted drops
-- v0.2.5
--   + Workbench: Added split screen mode with two stacked modules, a resizable splitter, swap control, and shared shell controls
--   + Workbench: Added Timepiece module with a large clock display for time, local clock, measures/beats, beats/ticks, seconds, samples, and frames
--   + Timepiece: Added optional full-width next marker bar below region progress and above the badges
--   + Timepiece: Added optional project position, region progress, play rate, context info, local time, and local date badges
--   + Timepiece: Added settings popup controls for status, BPM, signature, display mode, clock position, clock text visibility, and extra badges
--   + Timepiece: Added automatic play position/edit cursor behavior and optional top-aligned clock layout
--   + Timepiece: Added alarm and timer controls with bottom status bars and red clock feedback while ringing
--   + Timepiece: Improved large clock sizing, horizontal alignment, next marker persistence, and compact top layout spacing
--   + Workbench modules: Unified Plugin Browser, Instrument Rack, FX Chain Builder, and Timepiece settings access with right-aligned ... buttons
--   + Tags: Added global track tag module compatible with TK FX Browser tag storage
--   + Tags: Added search, tag creation, color editing, rename, global remove, and per-track/selected-track tag removal
--   + Tags: Added single and Ctrl multi-tag selection with TCP/MCP visibility filtering and matching REAPER track selection
--   + Tags: Added full track list navigation with active tag match highlighting even when TCP tracks are hidden
--   + Tags: Added context actions for selecting, muting, arming, soloing, solo-selecting, and clearing tags from tagged tracks
-- v0.2.4
--   + Workbench: Improved REAPER Theme color mapping using native main window, docker, list, transport, routing, marker, region, and meter theme colors
--   + Workbench: Added REAPER Theme - Panel and REAPER Theme - Color preset variants
--   + Workbench: Added contrast-aware text, dim text, and badge text selection for REAPER-derived theme presets
-- v0.2.3
--   + Instrument Rack: Added TK FX Browser Mini as an Add FX target
--   + Project Browser: Added compact list view with tighter row spacing
--   + Media Browser: Added compact list view with tighter row spacing
--   + Project Browser: Browsed folders are now added immediately instead of only filling the location field
--   + Action Clipboard: Added Ctrl+V paste from the system clipboard directly into hovered slots
--   + Action Clipboard: Added context menu paste from clipboard for individual slots
--   + Action Clipboard: Added support for pasted numeric command IDs, named commands, and exact action names
--   + Action Clipboard: Added hovered-slot keyboard interception so Ctrl+V works without first focusing Workbench
--   + Action Clipboard: Prevented REAPER's global Paste items/tracks command from being captured during slot paste
--   + Action Browser: Clipboard slot menus now follow the configured Action Clipboard slot count
--   + Project Browser: Added project audio preview discovery and playback for proxy and .tkprev preview files
--   + Project Browser: Added preview creation from full project render, time selection, or a custom audio file
--   + Project Browser: Added preview management popup to play, select active, and delete project previews
--   + Project Browser: Added persistent active preview selection per project
--   + Project Browser: Added preview volume, progress display, and compact playback controls
--   + Project Browser: Added theme-aware preview volume slider styling and a square No image fallback
--   + Project Browser: Custom audio preview file picker now opens in the project's folder
-- v0.2.2
--   + Action Clipboard: Added cross-platform TK Action Capture binaries for Windows, macOS and Linux delivery
--   + Native capture: Updated ReaPack delivery so platform artifacts install into the Workbench folder for manual UserPlugins copy
-- v0.2.1
--   + Action Browser: Added Action Clipboard footer with 5 recent, lockable action slots
--   + Action Browser: Added C shortcut to show or hide the Action Clipboard footer
--   + Action Browser: Added context menu actions to add actions to the clipboard or directly to a specific slot
--   + Action Clipboard: Added mappable run and lock-toggle slot scripts that work without Workbench being open
--   + Action Clipboard: Added persistent slot storage, external refresh handling, clearer lock styling, and shortcut details in tooltips
--   + Media Browser: Auto Categories now works on the currently open subfolder when folder browsing is active
--   + Project Browser: Added optional folder view for browsing subfolders in projects, project templates, and track templates
--   + Plugin Browser: Added virtual instrument new-track action with MIDI input selection
--   + Workbench: Added REAPER Theme preset for deriving Workbench colors from the active REAPER theme
--   + Workbench: Added mappable module actions for opening Home and each Workbench module, with automatic Workbench launch
--   + Workbench: Added separate Action Clipboard Actions and Module Actions folders for cleaner REAPER action organization
--   + Workbench: Added ExtState command handling for external clipboard and module action scripts
-- v0.1.7
--   + Project Browser: Added compact Workbench module for projects, project templates, and track templates
--   + Project Browser: Added per-type user locations, recursive scanning, search/filter, date sorting, cover previews, and open/insert actions
--   + Project Browser: Added read-only project metadata for BPM, signature, tracks, sample rate, modified date, and lightweight length detection
-- v0.1.5
--   + Media Browser: Added optional fade-in/fade-out handling for onboard audio previews
--   + Media Browser: Added configurable preview fade duration, disabled by default
--   + Media Browser: Added configurable audio switch gap and delayed source cleanup for onboard preview file switching
--   + Media Browser: Added optional tape-speed rate mode so pitch follows persistent rate changes while previewing files
--   + Media Browser: Added optional double-click-to-open behavior for folder browsing
--   + Plugin Browser: Added right-click screenshot capture with normal and OpenGL/DX modes, saved to the central TK FX BROWSER Screenshots folder
--   + Plugin Browser: Improved screenshot matching for x86/x86 bridged, Mono/Stereo, sanitized underscore, and manufacturer-prefix variants
--   + Control Room: Added monitor output modes for Stereo, Mono Sum, L/R Source, and L/R Speaker checks
--   + Control Room: Added setup and right-click lane controls for monitor output modes
--   + Control Room: Added Stereo and Mono Sum output modes for cue outputs, including setup and right-click lane controls
--   + Track Recall: Added multi-track save for selected tracks with automatic track-name based recall names
-- v0.1.4
--   + Media Browser: Added lazy per-location cache loading with explicit refresh
--   + Media Browser: Added compact folder browsing with subfolder rows
--   + Media Browser: Added folder cover-art thumbnails for cover/folder/front images
--   + Media Browser: Reworked media cache storage to avoid large Lua cache load errors
--   + Media Browser: Added option for random navigation during auto-preview playback
--   + Media Browser: Fixed drag-and-drop insertion into REAPER fixed item lanes
--   + Media Browser: Added audio-file context menu actions for RS5K and Cartridge loading
--   + Media Browser: Added RS5K Manager pad load/create/delete actions from the audio context menu
--   + Media Browser: Added RS5K Manager toggle action matching the standalone browser workflow
--   + Workbench: Added global tooltip enable and delay preferences
--   + Workbench: Added optional compact Info box footer with clipped text and hover details
--   + Workbench: Centralized Info box positioning so it stays aligned across modules
--   + Workbench: Improved module error display with compact diagnostics
--   + Color Studio: Added optional auto-apply for matching track color rules
-- v0.1.3
--   + Plugin Browser: Added option to return to Rack after adding FX from Rack
--   + Plugin Browser: Added option to return to FX Chain Builder after adding FX to Chain Builder
--   + Media Browser: Stop active preview playback when Workbench is closed by shortcut or action toggle
-- v0.1.2
--   + Added support for secondary Workbench launchers with separate script name and config file
-- v0.1.1
--   + Home: Added drag-and-drop module tile reordering with matching module dropdown order
--   + Instrument Rack: Added MIDI learn and hardware control support for rack macros
--   + Instrument Rack: Added absolute, relative, invert, range calibration, and sensitivity options for macro MIDI control
--   + Instrument Rack: Added global rack macro footer with 8 macro controls
--   + Instrument Rack: Added Assign to Macro workflow from pinned parameter controls
--   + Instrument Rack: Added project-persistent macro assignments with range and invert support
--   + Script Launcher: Added Capture Window for thumbnail screenshot capture
--   + Script Launcher: Added right-click context menu with Edit and Delete
--   + Script Launcher: Stabilized context-menu edit flow


local r = reaper

local SCRIPT_NAME = rawget(_G, "TK_WORKBENCH_SCRIPT_NAME") or "TK Workbench"
if not r.ImGui_CreateContext then
  r.ShowMessageBox("ReaImGui is required for TK Workbench.", SCRIPT_NAME, 0)
  return
end

local script_path = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
local sep = package.config:sub(1, 1)
package.path = script_path .. "?.lua;" .. script_path .. "?" .. sep .. "init.lua;" .. package.path

local Settings = require("core.settings")
local Theme = require("core.theme")
local Selection = require("core.selection")
local ModuleLoader = require("core.module_loader")
local UI = require("core.ui")
local UIScale = require("core.ui_scale")

local ctx = r.ImGui_CreateContext(SCRIPT_NAME)
local config_name = rawget(_G, "TK_WORKBENCH_CONFIG_NAME") or "config.json"
local config_path = script_path .. config_name
local settings = Settings.load(config_path)
UIScale.set(settings.ui_scale)

local app = {
  ctx = ctx,
  script_name = SCRIPT_NAME,
  script_path = script_path,
  config_path = config_path,
  settings = settings,
  selection = {},
  modules = {},
  modules_by_id = {},
  module_errors = {},
  error_counts = {},
  breadcrumb = nil,
  cache = {},
  status = "Ready",
  close_requested = false,
  settings_panel = nil
}
UI.configure_tooltips(app)
app.cache.saved_theme_preset = settings.theme_preset or "Graphite"

local HOME_MODULE_ID = "__home"
local MODULE_REORDER_PAYLOAD = "TK_WORKBENCH_MODULE_REORDER"
local MODULE_ACTION_EXT_SECTION = "TK_WORKBENCH_MODULE_ACTIONS"
local MODULE_ACTION_COMMAND_KEY = "command"
local MODULE_ACTION_RUNNING_KEY = "running"
local MODULE_ACTION_HEARTBEAT_KEY = "heartbeat"

local module_names = {
  "project_overview",
  "timepiece",
  "transport",
  "navigator",
  "project_browser",
  "action_browser",
  "action_clipboard",
  "script_launcher",
  "track_recall",
  "idea_vault",
  "track_tags",
  "automation_item_manager",
  "control_room",
  "send_studio",
  "instrument_rack",
  "fx_groups",
  "fx_chain_builder",
  "notes",
  "plugin_browser",
  "media_browser",
  "color_studio",
  "arrange_bg_presets",
  "calculator",
  "lyrics",
  "xy_pad",
  "render_hub",
  "sidechain"
}

local theme_color_fields = {
  { key = "window_bg", label = "Window" },
  { key = "child_bg", label = "Panel" },
  { key = "popup_bg", label = "Popup" },
  { key = "frame_bg", label = "Frame" },
  { key = "frame_hover", label = "Frame Hover" },
  { key = "header", label = "Header" },
  { key = "header_hover", label = "Header Hover" },
  { key = "separator", label = "Separator" },
  { key = "border", label = "Border" },
  { key = "text", label = "Text" },
  { key = "text_dim", label = "Dim Text" },
  { key = "badge_text", label = "Badge Text" },
  { key = "accent", label = "Accent" },
  { key = "accent_soft", label = "Accent Soft" },
  { key = "warning", label = "Warning" },
  { key = "danger", label = "Danger" }
}

local ui_scale_options = {
  { label = "85%", value = 0.85 },
  { label = "100%", value = 1.0 },
  { label = "115%", value = 1.15 },
  { label = "130%", value = 1.3 },
  { label = "150%", value = 1.5 },
  { label = "175%", value = 1.75 },
  { label = "200%", value = 2.0 }
}

local function set_ui_scale(value)
  local scale = UIScale.set(value)
  app.settings.ui_scale = scale
  return scale
end

local function ui_scale_label(scale)
  scale = UIScale.normalize(scale)
  for _, option in ipairs(ui_scale_options) do
    if math.abs(scale - option.value) < 0.01 then return option.label end
  end
  return tostring(math.floor(scale * 100 + 0.5)) .. "%"
end

local function get_scaled_font()
  local scale = set_ui_scale(app.settings.ui_scale or 1.0)
  if math.abs(scale - 1.0) < 0.01 then return nil end
  if not r.ImGui_CreateFont then return nil end
  app.cache.ui_fonts = app.cache.ui_fonts or {}
  if app.cache.ui_font_ctx ~= ctx then
    app.cache.ui_fonts = {}
    app.cache.ui_font_ctx = ctx
  end
  local font_size = math.max(10, math.floor(13 * scale + 0.5))
  local key = tostring(font_size)
  if app.cache.ui_fonts[key] then return app.cache.ui_fonts[key], font_size end
  local ok, font = pcall(r.ImGui_CreateFont, "sans-serif", font_size)
  if not ok or not font then return nil end
  if r.ImGui_Attach then pcall(r.ImGui_Attach, ctx, font) end
  app.cache.ui_fonts[key] = font
  return font, font_size
end

local function push_scaled_font()
  local font, font_size = get_scaled_font()
  if not font or not r.ImGui_PushFont then return false end
  local ok = pcall(r.ImGui_PushFont, ctx, font, font_size)
  return ok == true
end

local function pop_scaled_font(pushed)
  if pushed and r.ImGui_PopFont then pcall(r.ImGui_PopFont, ctx) end
end

local function save_settings()
  Settings.save(config_path, app.settings)
end

app.save_settings = save_settings

-- Both Workbench and Workbench 2 write to this one file, so every line says
-- which of them wrote it. Without that, two instances running side by side look
-- like one instance contradicting itself, and a pair of lines a second apart
-- reads as cause and effect when it may be two unrelated faults.
local function append_error_log(key, err, count)
  local file = io.open(script_path .. "workbench_errors.txt", "a")
  if not file then return end
  local repeats = (tonumber(count) or 1) > 1 and (" | x" .. tostring(count)) or ""
  file:write(os.date("%Y-%m-%d %H:%M:%S") .. " | " .. SCRIPT_NAME .. " | " .. tostring(key) .. " | " .. tostring(err) .. repeats .. "\n")
  file:close()
end

-- A repeat used to be dropped, so one failure and a thousand looked the same in
-- the file. Counted now, and written again as the count passes each mark, which
-- says whether something happened once or is happening every frame without
-- filling the file with identical lines.
local ERROR_LOG_MARKS = { [1] = true, [10] = true, [100] = true, [1000] = true, [10000] = true }

local function record_module_error(key, err)
  local message = tostring(err)
  -- The breadcrumb says where the module was when it failed. It is the module's
  -- own note, since the framework only ever sees the error, never the place.
  if app.breadcrumb and app.breadcrumb ~= "" then message = message .. "  [at " .. tostring(app.breadcrumb) .. "]" end
  if app.module_errors[key] ~= message then
    app.error_counts[key] = 1
    append_error_log(key, message, 1)
  else
    local count = (app.error_counts[key] or 0) + 1
    app.error_counts[key] = count
    if ERROR_LOG_MARKS[count] then append_error_log(key, message, count) end
  end
  app.module_errors[key] = message
end

local function clear_module_error(key)
  app.module_errors[key] = nil
end

app.record_module_error = record_module_error
app.clear_module_error = clear_module_error

local function find_module_index_by_id(id)
  for index, module in ipairs(app.modules) do
    if module.id == id then return index end
  end
  return nil
end

local function normalize_module_order()
  local loaded = {}
  for _, module in ipairs(app.modules) do loaded[module.id] = true end
  local order = type(app.settings.module_order) == "table" and app.settings.module_order or {}
  local normalized = {}
  local used = {}
  for _, id in ipairs(order) do
    if loaded[id] and not used[id] then
      normalized[#normalized + 1] = id
      used[id] = true
    end
  end
  for _, module in ipairs(app.modules) do
    if not used[module.id] then
      normalized[#normalized + 1] = module.id
      used[module.id] = true
    end
  end
  local changed = #normalized ~= #order
  if not changed then
    for index, id in ipairs(normalized) do
      if order[index] ~= id then changed = true; break end
    end
  end
  app.settings.module_order = normalized
  if changed then save_settings() end
  return normalized
end

local function save_module_order()
  local order = {}
  for _, module in ipairs(app.modules) do order[#order + 1] = module.id end
  app.settings.module_order = order
  save_settings()
end

local function apply_module_order()
  local order = normalize_module_order()
  local rank = {}
  for index, id in ipairs(order) do rank[id] = index end
  table.sort(app.modules, function(left, right)
    return (rank[left.id] or 9999) < (rank[right.id] or 9999)
  end)
end

local function move_module_to_target(source_id, target_id)
  if not source_id or not target_id or source_id == target_id then return false end
  local source_index = find_module_index_by_id(source_id)
  local target_index = find_module_index_by_id(target_id)
  if not source_index or not target_index then return false end
  local item = table.remove(app.modules, source_index)
  target_index = find_module_index_by_id(target_id) or target_index
  table.insert(app.modules, target_index, item)
  save_module_order()
  app.status = "Module order updated"
  return true
end

local function is_module_hidden(id)
  local hidden = app.settings.hidden_modules
  return type(hidden) == "table" and hidden[id] == true
end

local function set_module_hidden(id, hidden)
  local map = type(app.settings.hidden_modules) == "table" and app.settings.hidden_modules or {}
  if hidden then map[id] = true else map[id] = nil end
  app.settings.hidden_modules = map
  save_settings()
end

local function set_all_modules_hidden(hidden)
  local map = {}
  if hidden then
    for _, module in ipairs(app.modules) do map[module.id] = true end
  end
  app.settings.hidden_modules = map
  save_settings()
end

local function is_home_active()
  return app.settings.active_module == HOME_MODULE_ID
end

-- A pinned pane keeps the module it holds, so opening anything while one is
-- pinned has to land in the other pane. Only meaningful while the split is
-- actually on screen: on Home there is one pane and pinning cannot mean anything.
local function split_pin()
  if app.settings.split_view_enabled ~= true then return nil end
  if is_home_active() then return nil end
  local pin = app.settings.split_pinned_pane
  if pin == "primary" or pin == "secondary" then return pin end
  return nil
end

-- Returns true when it has handled the request itself, which is how it can sit
-- at the top of set_active_view without the two calling each other in circles.
local function route_to_unpinned_pane(id)
  if id == HOME_MODULE_ID or not app.modules_by_id[id] then return false end
  -- Home occupies the same setting the primary pane's module lives in, so going
  -- there forgets what was pinned. It is set aside on the way in and put back
  -- here, on the first module opened on the way out - which then lands in the
  -- other pane, exactly as it would have if Home had never happened.
  if is_home_active() then
    if app.settings.split_view_enabled ~= true or app.settings.split_pinned_pane ~= "primary" then return false end
    local restore = app.settings.split_pinned_return
    if not restore or restore == "" or restore == id or not app.modules_by_id[restore] then return false end
    app.settings.split_pinned_return = ""
    app.settings.active_module = restore
    app.settings.split_module = id
    save_settings()
    return true
  end
  if split_pin() ~= "primary" then return false end
  -- Clicking the pinned module itself: it is already on screen, and moving it
  -- into the other pane would leave the same module twice.
  if id == app.settings.active_module then return true end
  app.settings.split_module = id
  save_settings()
  return true
end

-- keep_pane is for the few places that mean a specific pane rather than "open
-- this module", such as swapping the two panes over.
local function set_active_view(id, keep_pane)
  if not keep_pane and route_to_unpinned_pane(id) then return end
  if id == HOME_MODULE_ID and split_pin() == "primary" then
    app.settings.split_pinned_return = app.settings.active_module
  end
  local current = app.settings.active_module
  if id == "plugin_browser" and current == "instrument_rack" then
    app.cache.plugin_browser_return_module = "instrument_rack"
  elseif id ~= "plugin_browser" then
    app.cache.plugin_browser_return_module = nil
  end
  app.settings.active_module = id
  save_settings()
end

app.set_active_view = set_active_view

local function open_horizontal_rack()
  local module = app.modules_by_id and app.modules_by_id.instrument_rack
  if module and module.launch_horizontal_rack then
    module.launch_horizontal_rack(app)
  else
    app.status = "Instrument Rack module not available"
  end
end

local HORIZONTAL_RACK_ENTRY = {
  id = "instrument_rack_horizontal",
  title = "Instrument Rack (H)",
  icon = "FX",
  synthetic = true,
  on_click = open_horizontal_rack,
}

local function horizontal_rack_entry_visible()
  return app.modules_by_id and app.modules_by_id.instrument_rack ~= nil and not is_module_hidden("instrument_rack")
end

local function process_module_action_commands()
  local command = r.GetExtState(MODULE_ACTION_EXT_SECTION, MODULE_ACTION_COMMAND_KEY) or ""
  if command == "" then return end
  r.SetExtState(MODULE_ACTION_EXT_SECTION, MODULE_ACTION_COMMAND_KEY, "", false)
  local action, target = command:match("^([%w_]+):(.+)$")
  -- "run" hands a module a verb of its own instead of just bringing it forward,
  -- so a single action script can dim the Control Room or fold a monitor. The
  -- module says what it understands; this only delivers.
  if action == "run" then
    local module_id, verb = target:match("^([%w_]+):(.+)$")
    local module = module_id and app.modules_by_id[module_id] or nil
    if not module then
      app.status = "Workbench module not found: " .. tostring(module_id)
    elseif type(module.handle_action) ~= "function" then
      app.status = tostring(module.title or module_id) .. " takes no actions"
    else
      local ok, err = pcall(module.handle_action, app, verb)
      if not ok then record_module_error(module_id .. ".action", err) end
    end
    return
  end
  if action ~= "open" or not target or target == "" then return end
  if target == HOME_MODULE_ID or app.modules_by_id[target] then
    set_active_view(target)
    local module = app.modules_by_id[target]
    app.status = "Opened " .. tostring(module and (module.title or module.id) or "Home")
  else
    app.status = "Workbench module not found: " .. tostring(target)
  end
end

local function get_active_module()
  local active_id = app.settings.active_module
  if active_id == HOME_MODULE_ID then return nil end
  if app.modules_by_id[active_id] then return app.modules_by_id[active_id] end
  if app.modules[1] then
    app.settings.active_module = app.modules[1].id
    save_settings()
    return app.modules[1]
  end
end

local function get_split_module()
  local active_id = app.settings.active_module
  local split_id = app.settings.split_module
  if split_id and split_id ~= "" and split_id ~= active_id and app.modules_by_id[split_id] then return app.modules_by_id[split_id] end
  for _, module in ipairs(app.modules) do
    if module.id ~= active_id then return module end
  end
end

local function split_view_available()
  return app.settings.split_view_enabled == true and not is_home_active() and get_active_module() ~= nil and get_split_module() ~= nil
end

local function split_orientation()
  return app.settings.split_orientation == "horizontal" and "horizontal" or "vertical"
end

local function set_split_module(id)
  if not id or id == "" or id == app.settings.active_module or not app.modules_by_id[id] then return false end
  -- "Show in split view" means the other pane, and with the secondary pinned the
  -- other pane is the primary one.
  if split_pin() == "secondary" then
    set_active_view(id)
    app.settings.split_view_enabled = true
    app.status = "Opened " .. tostring(app.modules_by_id[id].title or id)
    save_settings()
    return true
  end
  app.settings.split_module = id
  app.settings.split_view_enabled = true
  app.status = "Split module: " .. tostring(app.modules_by_id[id].title or id)
  save_settings()
  return true
end

-- Which end of the window a pane sits at, so the wording follows the layout
-- instead of talking about "primary" and "secondary" at the user.
local function pane_label(slot)
  if split_orientation() == "horizontal" then
    return slot == "primary" and "left" or "right"
  end
  return slot == "primary" and "top" or "bottom"
end

local function toggle_pane_pin(slot)
  local pinned = app.settings.split_pinned_pane == slot
  app.settings.split_pinned_pane = pinned and "" or slot
  app.settings.split_pinned_return = ""
  if pinned then
    app.status = "Pane unpinned"
  else
    app.status = "Pinned the " .. pane_label(slot) .. " pane - modules now open in the other one"
  end
  save_settings()
end

local function swap_split_modules()
  local split_module = get_split_module()
  local active_id = app.settings.active_module
  if not split_module or not active_id or active_id == HOME_MODULE_ID then return end
  app.settings.split_module = active_id
  set_active_view(split_module.id, true)
  -- The pin travels with the module rather than staying on the pane, so a swap
  -- moves what you pinned instead of pinning whatever landed there.
  local pin = app.settings.split_pinned_pane
  if pin == "primary" then
    app.settings.split_pinned_pane = "secondary"
  elseif pin == "secondary" then
    app.settings.split_pinned_pane = "primary"
  end
  app.settings.split_view_enabled = true
  app.status = "Split panes swapped"
  save_settings()
end

local function calc_text_width(value)
  if r.ImGui_CalcTextSize then
    local width = r.ImGui_CalcTextSize(ctx, tostring(value or ""))
    return tonumber(width) or 0
  end
  return #(tostring(value or "")) * 7
end

local function clamp(value, min_value, max_value)
  value = tonumber(value) or 0
  if value < min_value then return min_value end
  if value > max_value then return max_value end
  return value
end

local function split_rgba(color)
  color = math.floor(tonumber(color) or 0)
  if color < 0 then color = color + 0x100000000 end
  local red = math.floor(color / 0x1000000) % 0x100
  local green = math.floor(color / 0x10000) % 0x100
  local blue = math.floor(color / 0x100) % 0x100
  local alpha = color % 0x100
  return red, green, blue, alpha
end

local function rgba(red, green, blue, alpha)
  red = math.floor(clamp(red, 0, 255) + 0.5)
  green = math.floor(clamp(green, 0, 255) + 0.5)
  blue = math.floor(clamp(blue, 0, 255) + 0.5)
  alpha = math.floor(clamp(alpha or 255, 0, 255) + 0.5)
  return red * 0x1000000 + green * 0x10000 + blue * 0x100 + alpha
end

local function blend_color(first, second, amount)
  amount = clamp(amount, 0, 1)
  local ar, ag, ab, aa = split_rgba(first)
  local br, bg, bb, ba = split_rgba(second)
  return rgba(ar + (br - ar) * amount, ag + (bg - ag) * amount, ab + (bb - ab) * amount, aa + (ba - aa) * amount)
end

local function color_luminance(color)
  local red, green, blue = split_rgba(color)
  return (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255
end

local function contrast_from_background(background, amount)
  local target = color_luminance(background) > 0.5 and 0x000000FF or 0xFFFFFFFF
  return blend_color(background, target, amount)
end

local function ellipsize_text(value, max_width)
  value = tostring(value or "")
  if value == "" or calc_text_width(value) <= max_width then return value end
  -- Whole characters. Dropping one byte splits a Cyrillic or accented letter and
  -- the half left over is drawn as a placeholder box.
  while #value > 1 and calc_text_width(value .. "...") > max_width do
    local cut = #value
    while cut > 1 and value:byte(cut) >= 0x80 and value:byte(cut) < 0xC0 do cut = cut - 1 end
    value = value:sub(1, cut - 1)
  end
  return value .. "..."
end

local function card_title_lines(title, max_width)
  local lines = { "", "" }
  local line_index = 1
  for token in tostring(title or ""):gmatch("%S+") do
    local candidate = lines[line_index] == "" and token or (lines[line_index] .. " " .. token)
    if calc_text_width(candidate) > max_width and lines[line_index] ~= "" then
      line_index = math.min(2, line_index + 1)
      candidate = lines[line_index] == "" and token or (lines[line_index] .. " " .. token)
    end
    lines[line_index] = candidate
  end
  lines[1] = ellipsize_text(lines[1], max_width)
  lines[2] = ellipsize_text(lines[2], max_width)
  return lines
end

local function fallback_icon_text(module)
  local icon = tostring(module and module.icon or "")
  if icon ~= "" then return icon end
  local text = tostring(module and (module.title or module.id) or "")
  local result = ""
  for token in text:gmatch("%S+") do result = result .. token:sub(1, 1):upper() end
  if result == "" then result = "?" end
  return result:sub(1, 3)
end

local function draw_home_icon(draw_list, x, y, size, color)
  local left = x + size * 0.2
  local right = x + size * 0.8
  local top = y + size * 0.25
  local mid = y + size * 0.48
  local bottom = y + size * 0.82
  r.ImGui_DrawList_AddLine(draw_list, left, mid, x + size * 0.5, top, color, 2)
  r.ImGui_DrawList_AddLine(draw_list, x + size * 0.5, top, right, mid, color, 2)
  r.ImGui_DrawList_AddRect(draw_list, left + 2, mid, right - 2, bottom, color, 2, 0, 2)
  r.ImGui_DrawList_AddLine(draw_list, x + size * 0.48, bottom, x + size * 0.48, y + size * 0.64, color, 2)
  r.ImGui_DrawList_AddLine(draw_list, x + size * 0.48, y + size * 0.64, x + size * 0.62, y + size * 0.64, color, 2)
  r.ImGui_DrawList_AddLine(draw_list, x + size * 0.62, y + size * 0.64, x + size * 0.62, bottom, color, 2)
end

local function draw_split_icon(draw_list, x, y, size, color)
  local left = x + size * 0.2
  local right = x + size * 0.8
  local top = y + size * 0.2
  local bottom = y + size * 0.8
  local mid = y + size * 0.5
  r.ImGui_DrawList_AddRect(draw_list, left, top, right, mid - 2, color, 2, 0, 2)
  r.ImGui_DrawList_AddRect(draw_list, left, mid + 2, right, bottom, color, 2, 0, 2)
end

-- A thumbtack: head, collar and needle. Filled once the pane is pinned so the
-- state reads at a glance from across the window, outlined while it is only an
-- offer to pin.
local function draw_pin_icon(draw_list, cx, cy, size, color, filled)
  local head = size * 0.30
  local head_y = cy - size * 0.18
  local collar = size * 0.34
  if filled then
    r.ImGui_DrawList_AddCircleFilled(draw_list, cx, head_y, head, color, 12)
    r.ImGui_DrawList_AddRectFilled(draw_list, cx - collar, head_y + head * 0.55, cx + collar, head_y + head * 0.55 + size * 0.13, color, 1)
  else
    r.ImGui_DrawList_AddCircle(draw_list, cx, head_y, head, color, 12, 1.3)
    r.ImGui_DrawList_AddLine(draw_list, cx - collar, head_y + head * 0.9, cx + collar, head_y + head * 0.9, color, 1.3)
  end
  r.ImGui_DrawList_AddLine(draw_list, cx, head_y + head * 0.9, cx, cy + size * 0.5, color, filled and 1.8 or 1.3)
end

local function draw_module_icon(draw_list, module, cx, cy, size, color)
  local id = module and module.id or ""
  local s = size / 48
  local left = cx - size * 0.5
  local right = cx + size * 0.5
  local top = cy - size * 0.5
  local bottom = cy + size * 0.5
  local function L(o) return left + o * s end
  local function R(o) return right - o * s end
  local function T(o) return top + o * s end
  local function B(o) return bottom - o * s end
  local function MX(o) return cx + (o or 0) * s end
  local function MY(o) return cy + (o or 0) * s end
  local function W(t) return math.max(1, (t or 1) * s) end
  local function RD(rd) return (rd or 1) * s end
  if id == "project_overview" then
    r.ImGui_DrawList_AddCircle(draw_list, cx, cy, size * 0.34, color, 32, W(2))
    r.ImGui_DrawList_AddCircleFilled(draw_list, cx, T(16), RD(2.2), color, 12)
    r.ImGui_DrawList_AddLine(draw_list, cx, MY(-2), cx, B(14), color, W(3))
    r.ImGui_DrawList_AddLine(draw_list, MX(-5), MY(-2), cx, MY(-2), color, W(3))
    r.ImGui_DrawList_AddLine(draw_list, MX(-5), B(14), MX(5), B(14), color, W(3))
  elseif id == "navigator" then
    r.ImGui_DrawList_AddRect(draw_list, L(8), T(11), R(8), B(11), color, RD(2), 0, W(1.6))
    r.ImGui_DrawList_AddLine(draw_list, L(8), T(15), R(8), T(15), color, W(1.2))
    r.ImGui_DrawList_AddRectFilled(draw_list, MX(-6), MY(-1), MX(1), MY(3), color, RD(1))
    r.ImGui_DrawList_AddRect(draw_list, MX(-2), T(16), R(11), B(14), color, RD(1.5), 0, W(1.6))
  elseif id == "timepiece" then
    r.ImGui_DrawList_AddCircle(draw_list, cx, cy, size * 0.34, color, 32, W(2))
    r.ImGui_DrawList_AddCircleFilled(draw_list, cx, cy, RD(2.4), color, 12)
    r.ImGui_DrawList_AddLine(draw_list, cx, cy, cx, T(15), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, cx, cy, R(16), MY(7), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, cx, T(10), cx, T(14), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, cx, B(14), cx, B(10), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(10), cy, L(14), cy, color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, R(14), cy, R(10), cy, color, W(2))
  elseif id == "transport" then
    r.ImGui_DrawList_AddRect(draw_list, L(6), T(10), R(6), B(10), color, RD(6), 0, W(2))
    r.ImGui_DrawList_AddTriangleFilled(draw_list, L(18), T(18), L(18), B(18), R(16), cy, color)
  elseif id == "action_browser" then
    r.ImGui_DrawList_AddRect(draw_list, L(7), T(9), R(7), B(9), color, RD(4), 0, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(14), T(18), L(20), MY(-1), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(20), MY(-1), L(14), MY(8), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(25), MY(8), L(34), MY(8), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(14), B(17), R(16), B(17), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(14), B(10), R(24), B(10), color, W(2))
  elseif id == "action_clipboard" then
    r.ImGui_DrawList_AddRect(draw_list, L(9), T(10), R(9), B(5), color, RD(4), 0, W(2))
    r.ImGui_DrawList_AddRect(draw_list, MX(-10), T(5), MX(10), T(15), color, RD(4), 0, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(17), T(25), L(21), T(29), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(21), T(29), L(27), T(20), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(32), T(26), R(16), T(26), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(17), T(36), L(21), T(40), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(21), T(40), L(27), T(31), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(32), T(37), R(16), T(37), color, W(2))
  elseif id == "script_launcher" then
    r.ImGui_DrawList_AddRect(draw_list, L(7), T(8), R(7), B(8), color, RD(4), 0, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(17), T(16), L(17), B(16), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(17), T(16), R(16), cy, color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, R(16), cy, L(17), B(16), color, W(2))
  elseif id == "track_recall" then
    r.ImGui_DrawList_AddLine(draw_list, L(14), T(8), R(14), T(8), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(14), B(8), R(14), B(8), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(16), T(10), R(16), B(10), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, R(16), T(10), L(16), B(10), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(20), T(15), cx, MY(-2), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, R(20), T(15), cx, MY(-2), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, cx, MY(3), L(21), B(14), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, cx, MY(3), R(21), B(14), color, W(2))
  elseif id == "idea_vault" then
    r.ImGui_DrawList_AddCircle(draw_list, cx, T(19), RD(9), color, 24, W(2))
    r.ImGui_DrawList_AddLine(draw_list, MX(-4), T(27), MX(-4), B(15), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, MX(4), T(27), MX(4), B(15), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, MX(-5), B(14), MX(5), B(14), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, MX(-4), B(10), MX(4), B(10), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, MX(-2), B(7), MX(2), B(7), color, W(2))
  elseif id == "track_tags" then
    r.ImGui_DrawList_AddLine(draw_list, L(10), T(14), R(16), T(14), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, R(16), T(14), R(8), cy, color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, R(8), cy, R(16), B(14), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, R(16), B(14), L(10), B(14), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(10), B(14), L(10), T(14), color, W(2))
    r.ImGui_DrawList_AddCircleFilled(draw_list, L(18), cy, RD(3), color, 12)
    r.ImGui_DrawList_AddLine(draw_list, MX(-4), MY(-7), MX(9), MY(6), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, MX(3), MY(-7), MX(-4), cy, color, W(2))
  elseif id == "automation_item_manager" then
    r.ImGui_DrawList_AddLine(draw_list, L(6), B(12), MX(-8), MY(7), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, MX(-8), MY(7), MX(7), MY(-8), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, MX(7), MY(-8), R(7), T(14), color, W(2))
    r.ImGui_DrawList_AddCircleFilled(draw_list, L(6), B(12), RD(4), color, 12)
    r.ImGui_DrawList_AddCircleFilled(draw_list, MX(-8), MY(7), RD(4), color, 12)
    r.ImGui_DrawList_AddCircleFilled(draw_list, MX(7), MY(-8), RD(4), color, 12)
    r.ImGui_DrawList_AddCircleFilled(draw_list, R(7), T(14), RD(4), color, 12)
  elseif id == "control_room" then
    r.ImGui_DrawList_AddRect(draw_list, L(8), T(8), R(8), B(8), color, RD(4), 0, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(17), B(13), L(17), T(18), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, cx, B(13), cx, T(13), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, R(17), B(13), R(17), T(23), color, W(2))
    r.ImGui_DrawList_AddCircleFilled(draw_list, L(17), MY(6), RD(4), color, 12)
    r.ImGui_DrawList_AddCircleFilled(draw_list, cx, MY(-4), RD(4), color, 12)
    r.ImGui_DrawList_AddCircleFilled(draw_list, R(17), MY(10), RD(4), color, 12)
  elseif id == "send_studio" then
    r.ImGui_DrawList_AddCircleFilled(draw_list, L(12), cy, RD(4), color, 16)
    r.ImGui_DrawList_AddLine(draw_list, L(15), cy, MX(-2), cy, color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, MX(-2), cy, MX(-2), T(15), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, MX(-2), cy, MX(-2), B(15), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, MX(-2), T(15), R(13), T(15), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, MX(-2), B(15), R(13), B(15), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, R(17), T(11), R(11), T(15), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, R(17), T(19), R(11), T(15), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, R(17), B(19), R(11), B(15), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, R(17), B(11), R(11), B(15), color, W(2))
  elseif id == "instrument_rack" then
    r.ImGui_DrawList_AddRect(draw_list, L(7), T(8), R(7), B(8), color, RD(3), 0, W(2))
    for index = 0, 3 do
      local key_x = L(12 + index * 9)
      r.ImGui_DrawList_AddLine(draw_list, key_x, cy, key_x, B(10), color, W(2))
    end
    r.ImGui_DrawList_AddLine(draw_list, L(8), cy, R(8), cy, color, W(2))
  elseif id == "instrument_rack_horizontal" then
    r.ImGui_DrawList_AddRect(draw_list, L(8), T(7), R(8), B(7), color, RD(3), 0, W(2))
    for index = 0, 3 do
      local key_y = T(12 + index * 9)
      r.ImGui_DrawList_AddLine(draw_list, cx, key_y, R(10), key_y, color, W(2))
    end
    r.ImGui_DrawList_AddLine(draw_list, cx, T(8), cx, B(8), color, W(2))
  elseif id == "fx_chain_builder" then
    r.ImGui_DrawList_AddRect(draw_list, L(6), MY(-13), R(6), MY(13), color, RD(4), 0, W(2))
    r.ImGui_DrawList_AddRect(draw_list, L(10), MY(-6), L(20), MY(4), color, RD(2), 0, W(2))
    r.ImGui_DrawList_AddRect(draw_list, L(23), MY(-6), L(33), MY(4), color, RD(2), 0, W(2))
  elseif id == "fx_groups" then
    r.ImGui_DrawList_AddRect(draw_list, L(7), MY(-13), L(19), MY(-1), color, RD(3), 0, W(2))
    r.ImGui_DrawList_AddRect(draw_list, R(7), MY(1), R(19), MY(13), color, RD(3), 0, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(19), MY(-7), R(19), MY(7), color, W(2))
    r.ImGui_DrawList_AddCircleFilled(draw_list, L(19), MY(-7), RD(3), color, 12)
    r.ImGui_DrawList_AddCircleFilled(draw_list, R(19), MY(7), RD(3), color, 12)
  elseif id == "notes" then
    r.ImGui_DrawList_AddRect(draw_list, L(8), T(5), R(8), B(5), color, RD(4), 0, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(14), T(15), R(14), T(15), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(14), T(25), R(18), T(25), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(14), T(35), R(22), T(35), color, W(2))
  elseif id == "plugin_browser" then
    r.ImGui_DrawList_AddRect(draw_list, L(11), MY(-13), R(13), MY(13), color, RD(4), 0, W(2))
    r.ImGui_DrawList_AddLine(draw_list, R(13), MY(-6), R(6), MY(-6), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, R(13), MY(6), R(6), MY(6), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(6), cy, L(11), cy, color, W(2))
  elseif id == "media_browser" then
    r.ImGui_DrawList_AddRect(draw_list, L(6), T(9), R(6), B(9), color, RD(4), 0, W(2))
    for index = 0, 3 do
      local film_x = L(12 + index * 9)
      r.ImGui_DrawList_AddLine(draw_list, film_x, T(10), film_x, T(17), color, W(2))
      r.ImGui_DrawList_AddLine(draw_list, film_x, B(17), film_x, B(10), color, W(2))
    end
    r.ImGui_DrawList_AddLine(draw_list, L(14), cy, MX(-6), MY(-8), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, MX(-6), MY(-8), MX(6), MY(8), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, MX(6), MY(8), R(14), cy, color, W(2))
  elseif id == "arrange_bg_presets" then
    r.ImGui_DrawList_AddRect(draw_list, L(6), T(9), R(6), B(9), color, RD(3), 0, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(7), MY(-7), R(7), MY(-7), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(7), MY(4), R(7), MY(4), color, W(2))
    for index = 0, 2 do
      local grid_x = L(15 + index * 11)
      r.ImGui_DrawList_AddLine(draw_list, grid_x, T(12), grid_x, B(12), color, W(1))
    end
  elseif id == "sidechain" then
    -- Two waveforms: one ducking under the other where they meet.
    r.ImGui_DrawList_AddLine(draw_list, L(8), MY(-9), L(18), MY(-9), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(18), MY(-9), MX(-2), MY(-2), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, MX(-2), MY(-2), MX(6), MY(-2), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, MX(6), MY(-2), MX(12), MY(-9), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, MX(12), MY(-9), R(8), MY(-9), color, W(2))
    r.ImGui_DrawList_AddCircleFilled(draw_list, MX(2), MY(9), RD(3), color, 12)
    r.ImGui_DrawList_AddLine(draw_list, L(8), MY(9), MX(-2), MY(9), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, MX(6), MY(9), R(8), MY(9), color, W(2))
  elseif id == "render_hub" then
    r.ImGui_DrawList_AddLine(draw_list, cx, T(10), cx, MY(4), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, MX(-7), MY(-3), cx, MY(4), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, MX(7), MY(-3), cx, MY(4), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(10), B(17), L(10), B(10), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, L(10), B(10), R(10), B(10), color, W(2))
    r.ImGui_DrawList_AddLine(draw_list, R(10), B(17), R(10), B(10), color, W(2))
  elseif id == "calculator" then
    r.ImGui_DrawList_AddRect(draw_list, L(8), T(6), R(8), B(6), color, RD(3), 0, W(2))
    r.ImGui_DrawList_AddRect(draw_list, L(13), T(11), R(13), T(22), color, RD(2), 0, W(1))
    for by = 0, 1 do
      for bx = 0, 2 do
        r.ImGui_DrawList_AddCircleFilled(draw_list, L(17 + bx * 8), MY(7 + by * 9), RD(2), color, 10)
      end
    end
  else
    local icon = fallback_icon_text(module)
    r.ImGui_DrawList_AddCircle(draw_list, cx, cy, size * 0.34, color, 32, W(2))
    local text_w = calc_text_width(icon)
    r.ImGui_DrawList_AddText(draw_list, cx - text_w * 0.5, cy - r.ImGui_GetTextLineHeight(ctx) * 0.5, color, icon)
  end
end

local function draw_module_card(module, card_width, card_height)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local active = app.settings.active_module == module.id
  r.ImGui_PushID(ctx, module.id)
  local clicked = r.ImGui_InvisibleButton(ctx, "##home_module_card", card_width, card_height)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local x1, y1 = r.ImGui_GetItemRectMin(ctx)
  local x2, y2 = r.ImGui_GetItemRectMax(ctx)
  local bg = active and Theme.colors.accent_soft or (hovered and Theme.colors.frame_hover or Theme.colors.frame_bg)
  local border = active and Theme.colors.accent or Theme.colors.border
  local icon_color = Theme.text_for_background(bg, (hovered or active) and Theme.colors.accent or Theme.colors.text_dim, nil, 3)
  local title_color = Theme.text_for_background(bg, Theme.colors.text, nil, 4.5)
  local pad = UIScale.round(7)
  local icon_size = UIScale.round(48)
  r.ImGui_DrawList_AddRectFilled(draw_list, x1, y1, x2, y2, bg, UIScale.px(6))
  r.ImGui_DrawList_AddRect(draw_list, x1, y1, x2, y2, border, UIScale.px(6), 0, active and UIScale.px(1.6) or UIScale.px(0.8))
  draw_module_icon(draw_list, module, (x1 + x2) * 0.5, y1 + UIScale.round(36), icon_size, icon_color)
  local title = tostring(module.title or module.id or "Module")
  local lines = card_title_lines(title, card_width - pad * 2)
  local line_h = r.ImGui_GetTextLineHeight(ctx)
  local text_y = y2 - UIScale.round(12) - line_h * ((lines[2] ~= "" and 2 or 1))
  r.ImGui_DrawList_PushClipRect(draw_list, x1 + pad, y1 + UIScale.round(5), x2 - pad, y2 - UIScale.round(5), true)
  for index = 1, 2 do
    if lines[index] ~= "" then
      local text_w = calc_text_width(lines[index])
      r.ImGui_DrawList_AddText(draw_list, x1 + math.max(pad, (card_width - text_w) * 0.5), text_y + (index - 1) * line_h, title_color, lines[index])
    end
  end
  r.ImGui_DrawList_PopClipRect(draw_list)
  if not module.synthetic and r.ImGui_BeginDragDropSource and r.ImGui_SetDragDropPayload then
    local source_flags = r.ImGui_DragDropFlags_SourceNoPreviewTooltip and r.ImGui_DragDropFlags_SourceNoPreviewTooltip() or 0
    if r.ImGui_BeginDragDropSource(ctx, source_flags) then
      r.ImGui_SetDragDropPayload(ctx, MODULE_REORDER_PAYLOAD, module.id)
      r.ImGui_Text(ctx, title)
      r.ImGui_EndDragDropSource(ctx)
    end
  end
  if not module.synthetic and r.ImGui_BeginDragDropTarget and r.ImGui_AcceptDragDropPayload and r.ImGui_BeginDragDropTarget(ctx) then
    r.ImGui_DrawList_AddRect(draw_list, x1 + 2, y1 + 2, x2 - 2, y2 - 2, Theme.colors.accent, 6, 0, 2)
    local ok, payload = r.ImGui_AcceptDragDropPayload(ctx, MODULE_REORDER_PAYLOAD)
    if ok and payload and payload ~= module.id then app.cache.pending_module_reorder = { source = payload, target = module.id } end
    r.ImGui_EndDragDropTarget(ctx)
  end
  if clicked then
    if module.on_click then module.on_click() else set_active_view(module.id) end
  end
  if hovered then r.ImGui_SetTooltip(ctx, title .. (module.synthetic and "" or "\nDrag to reorder")) end
  r.ImGui_PopID(ctx)
end

local function draw_home_view()
  local _, available_h = r.ImGui_GetContentRegionAvail(ctx)
  local status_h = app.settings.show_status and UI.info_line_height(ctx) or 0
  local content_h = math.max(40, (available_h or 240) - status_h)
  local child_visible = r.ImGui_BeginChild(ctx, "##home_module_tiles", 0, content_h, 0)
  if child_visible then
    local avail_w = r.ImGui_GetContentRegionAvail(ctx) or 1
    local gap = UIScale.gap(10)
    local min_card_w = UIScale.round(118)
    local columns = math.max(1, math.floor((avail_w + gap) / (min_card_w + gap)))
    local card_w = math.max(1, math.floor((avail_w - gap * (columns - 1)) / columns))
    while columns > 1 and card_w < min_card_w do
      columns = columns - 1
      card_w = math.max(1, math.floor((avail_w - gap * (columns - 1)) / columns))
    end
    local card_h = math.max(UIScale.round(104), math.ceil(r.ImGui_GetTextLineHeight(ctx) * 5.8))
    local visible_index = 0
    for _, module in ipairs(app.modules) do
      if not is_module_hidden(module.id) then
        visible_index = visible_index + 1
        draw_module_card(module, card_w, card_h)
        if visible_index % columns ~= 0 then r.ImGui_SameLine(ctx, 0, gap) end
      end
    end
    if horizontal_rack_entry_visible() then
      visible_index = visible_index + 1
      draw_module_card(HORIZONTAL_RACK_ENTRY, card_w, card_h)
      if visible_index % columns ~= 0 then r.ImGui_SameLine(ctx, 0, gap) end
    end
    local pending = app.cache.pending_module_reorder
    if pending then
      app.cache.pending_module_reorder = nil
      move_module_to_target(pending.source, pending.target)
    end
    r.ImGui_EndChild(ctx)
  end
end

local function draw_top_bar()
  local avail_w = r.ImGui_GetContentRegionAvail(ctx)
  local active_module = get_active_module()
  local title = is_home_active() and "Home" or tostring(active_module and (active_module.title or active_module.id) or "Module")
  local dot_size = UIScale.round(14)
  local dot_gap = UIScale.gap(8)
  local dot_unit = dot_size / 14
  r.ImGui_TextColored(ctx, Theme.colors.accent, SCRIPT_NAME)
  r.ImGui_SameLine(ctx, math.max(UIScale.round(120), avail_w - (dot_size * 3) - (dot_gap * 2)))
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local pin_x, pin_y = r.ImGui_GetCursorScreenPos(ctx)
  local pin_active = app.settings.auto_collapse_keep_expanded == true
  local pin_color = pin_active and Theme.colors.accent or Theme.colors.text_dim
  r.ImGui_DrawList_AddCircleFilled(draw_list, pin_x + dot_size * 0.5, pin_y + dot_size * 0.5, dot_size * 0.5, pin_active and Theme.colors.accent_soft or Theme.colors.frame_bg)
  r.ImGui_DrawList_AddCircle(draw_list, pin_x + dot_size * 0.5, pin_y + dot_size * 0.5, dot_size * 0.5, pin_active and Theme.colors.accent or Theme.colors.border, 16, 1)
  r.ImGui_DrawList_AddLine(draw_list, pin_x + 5 * dot_unit, pin_y + 4 * dot_unit, pin_x + 9 * dot_unit, pin_y + 4 * dot_unit, pin_color, UIScale.px(1.5))
  r.ImGui_DrawList_AddLine(draw_list, pin_x + 7 * dot_unit, pin_y + 4 * dot_unit, pin_x + 7 * dot_unit, pin_y + 10 * dot_unit, pin_color, UIScale.px(1.5))
  r.ImGui_DrawList_AddLine(draw_list, pin_x + 5 * dot_unit, pin_y + 10 * dot_unit, pin_x + 9 * dot_unit, pin_y + 10 * dot_unit, pin_color, UIScale.px(1.5))
  if r.ImGui_InvisibleButton(ctx, "##workbench_keep_expanded_pin", dot_size, dot_size) then
    app.settings.auto_collapse_keep_expanded = not pin_active
    if app.settings.auto_collapse_keep_expanded then
      app.cache.auto_collapse_collapsed = false
      app.cache.auto_collapse_force_restore = true
      app.status = "Workbench pinned open"
    else
      app.cache.auto_collapse_last_hover_time = r.time_precise and r.time_precise() or os.clock()
      app.status = "Workbench auto-collapse active"
    end
    save_settings()
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, pin_active and "Allow auto-collapse" or "Keep Workbench expanded") end
  r.ImGui_SameLine(ctx, 0, dot_gap)
  local settings_x, settings_y = r.ImGui_GetCursorScreenPos(ctx)
  local dot_y = settings_y + dot_size * 0.5
  r.ImGui_DrawList_AddCircleFilled(draw_list, settings_x + dot_size * 0.5, dot_y, dot_size * 0.5, 0xF2F2F2FF)
  r.ImGui_DrawList_AddCircle(draw_list, settings_x + dot_size * 0.5, dot_y, dot_size * 0.5, 0x8F9AA8FF, 16, 1)
  if r.ImGui_InvisibleButton(ctx, "##workbench_settings_dot", dot_size, dot_size) then
    app.settings_panel = "preferences"
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Settings") end
  r.ImGui_SameLine(ctx, 0, dot_gap)
  local close_x, close_y = r.ImGui_GetCursorScreenPos(ctx)
  local close_y_mid = close_y + dot_size * 0.5
  r.ImGui_DrawList_AddCircleFilled(draw_list, close_x + dot_size * 0.5, close_y_mid, dot_size * 0.5, 0xF7768EFF)
  r.ImGui_DrawList_AddCircle(draw_list, close_x + dot_size * 0.5, close_y_mid, dot_size * 0.5, 0x3A1018FF, 16, 1)
  if r.ImGui_InvisibleButton(ctx, "##workbench_close_dot", dot_size, dot_size) then app.close_requested = true end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Close") end
  local home_size = r.ImGui_GetFrameHeight(ctx)
  local home_x, home_y = r.ImGui_GetCursorScreenPos(ctx)
  if r.ImGui_InvisibleButton(ctx, "##tk_workbench_home", home_size, home_size) then set_active_view(HOME_MODULE_ID) end
  local home_hovered = r.ImGui_IsItemHovered(ctx)
  local home_color = (is_home_active() or home_hovered) and Theme.colors.accent or Theme.colors.text_dim
  r.ImGui_DrawList_AddRectFilled(draw_list, home_x, home_y, home_x + home_size, home_y + home_size, is_home_active() and Theme.colors.accent_soft or Theme.colors.frame_bg, UIScale.px(4))
  r.ImGui_DrawList_AddRect(draw_list, home_x, home_y, home_x + home_size, home_y + home_size, home_hovered and Theme.colors.accent or Theme.colors.border, UIScale.px(4), 0, UIScale.px(1))
  local icon_inset = UIScale.round(3)
  draw_home_icon(draw_list, home_x + icon_inset, home_y + icon_inset, home_size - icon_inset * 2, home_color)
  if home_hovered then r.ImGui_SetTooltip(ctx, "Home") end
  r.ImGui_SameLine(ctx, 0, UIScale.gap(6))
  local split_x, split_y = r.ImGui_GetCursorScreenPos(ctx)
  local split_clicked = r.ImGui_InvisibleButton(ctx, "##tk_workbench_split", home_size, home_size)
  local split_right_clicked = r.ImGui_IsItemClicked and r.ImGui_IsItemClicked(ctx, 1)
  if split_clicked then r.ImGui_OpenPopup(ctx, "##tk_workbench_split_menu") end
  if split_right_clicked then
    local enabled = app.settings.split_view_enabled == true
    app.settings.split_view_enabled = not enabled
    app.status = app.settings.split_view_enabled and "Split view enabled" or "Split view disabled"
    save_settings()
  end
  local split_hovered = r.ImGui_IsItemHovered(ctx)
  local split_active = split_view_available()
  local split_color = (split_active or split_hovered) and Theme.colors.accent or Theme.colors.text_dim
  r.ImGui_DrawList_AddRectFilled(draw_list, split_x, split_y, split_x + home_size, split_y + home_size, split_active and Theme.colors.accent_soft or Theme.colors.frame_bg, UIScale.px(4))
  r.ImGui_DrawList_AddRect(draw_list, split_x, split_y, split_x + home_size, split_y + home_size, split_hovered and Theme.colors.accent or Theme.colors.border, UIScale.px(4), 0, UIScale.px(1))
  draw_split_icon(draw_list, split_x + icon_inset, split_y + icon_inset, home_size - icon_inset * 2, split_color)
  if split_hovered then r.ImGui_SetTooltip(ctx, "Split view\nRight-click: toggle on/off") end
  if r.ImGui_BeginPopup(ctx, "##tk_workbench_split_menu") then
    local enabled = app.settings.split_view_enabled == true
    local changed, value = r.ImGui_Checkbox(ctx, "Split View", enabled)
    if changed then
      app.settings.split_view_enabled = value
      app.status = value and "Split view enabled" or "Split view disabled"
      save_settings()
    end
    r.ImGui_Separator(ctx)
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Secondary")
    for _, candidate in ipairs(app.modules) do
      if candidate.id ~= app.settings.active_module and not is_module_hidden(candidate.id) then
        local selected = app.settings.split_module == candidate.id
        if r.ImGui_Selectable(ctx, candidate.title or candidate.id, selected) then set_split_module(candidate.id) end
        if selected then r.ImGui_SetItemDefaultFocus(ctx) end
      end
    end
    r.ImGui_Separator(ctx)
    for _, slot in ipairs({ "primary", "secondary" }) do
      local label = "Keep " .. pane_label(slot) .. " pane"
      if r.ImGui_MenuItem(ctx, label, nil, app.settings.split_pinned_pane == slot, enabled) then
        toggle_pane_pin(slot)
      end
    end
    r.ImGui_Separator(ctx)
    local is_horizontal = split_orientation() == "horizontal"
    if r.ImGui_MenuItem(ctx, "Side by side", nil, is_horizontal) then
      app.settings.split_orientation = is_horizontal and "vertical" or "horizontal"
      app.status = is_horizontal and "Split stacked" or "Split side by side"
      save_settings()
    end
    if r.ImGui_MenuItem(ctx, "Swap panes", nil, false, split_view_available()) then swap_split_modules() end
    if r.ImGui_MenuItem(ctx, "Close split", nil, false, enabled) then
      app.settings.split_view_enabled = false
      app.status = "Split view disabled"
      save_settings()
    end
    r.ImGui_EndPopup(ctx)
  end
  r.ImGui_SameLine(ctx, 0, UIScale.gap(6))
  local combo_flags = r.ImGui_ComboFlags_HeightLargest and r.ImGui_ComboFlags_HeightLargest() or 0
  r.ImGui_PushItemWidth(ctx, -1)
  if r.ImGui_BeginCombo(ctx, "##tk_workbench_module_select", title, combo_flags) then
    for _, candidate in ipairs(app.modules) do
      if not is_module_hidden(candidate.id) or app.settings.active_module == candidate.id then
        local selected = app.settings.active_module == candidate.id
        if r.ImGui_Selectable(ctx, candidate.title or candidate.id, selected) then
          set_active_view(candidate.id)
        end
        if selected then r.ImGui_SetItemDefaultFocus(ctx) end
      end
    end
    if horizontal_rack_entry_visible() then
      if r.ImGui_Selectable(ctx, HORIZONTAL_RACK_ENTRY.title, false) then
        open_horizontal_rack()
      end
    end
    r.ImGui_EndCombo(ctx)
  end
  r.ImGui_PopItemWidth(ctx)
  r.ImGui_Separator(ctx)
end

local function draw_theme_preview(colors)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local size = UIScale.round(18)
  local gap = UIScale.gap(6)
  local swatches = { colors.window_bg, colors.child_bg, colors.frame_bg, colors.accent, colors.warning, colors.danger }
  for index, color in ipairs(swatches) do
    local left = x + (index - 1) * (size + gap)
    r.ImGui_DrawList_AddRectFilled(draw_list, left, y, left + size, y + size, color, UIScale.px(3))
    r.ImGui_DrawList_AddRect(draw_list, left, y, left + size, y + size, Theme.colors.border, UIScale.px(3), 0, UIScale.px(1))
  end
  r.ImGui_Dummy(ctx, (#swatches * (size + gap)) - gap, size)
end

local function trim_text(value)
  return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

local function is_reserved_theme_name(name)
  local normalized = trim_text(name):lower()
  if normalized == "unsaved custom" then return true end
  if Theme.is_reserved_preset_name and Theme.is_reserved_preset_name(normalized) then return true end
  for preset_name in pairs(Theme.presets or {}) do
    if preset_name:lower() == normalized then return true end
  end
  return false
end

local function draw_theme_settings_body()
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Preset")
    local current = app.settings.theme_preset or "Graphite"
    if r.ImGui_BeginCombo(ctx, "##theme_preset", current) then
      for _, name in ipairs(Theme.get_preset_names()) do
        local selected = current == name
        if r.ImGui_Selectable(ctx, name, selected) then
          app.settings.theme_preset = Theme.set_preset(name, app.settings.custom_themes)
          app.cache.saved_theme_preset = app.settings.theme_preset
          app.status = "Theme preset: " .. app.settings.theme_preset
          save_settings()
        end
        if selected then r.ImGui_SetItemDefaultFocus(ctx) end
      end
      if next(app.settings.custom_themes or {}) then r.ImGui_Separator(ctx) end
      local custom_names = {}
      for name in pairs(app.settings.custom_themes or {}) do custom_names[#custom_names + 1] = name end
      table.sort(custom_names)
      for _, name in ipairs(custom_names) do
        local selected = current == name
        if r.ImGui_Selectable(ctx, name .. "##custom_theme", selected) then
          app.settings.theme_preset = Theme.set_preset(name, app.settings.custom_themes)
          app.settings.custom_theme_name = name
          app.cache.saved_theme_preset = app.settings.theme_preset
          app.status = "Theme preset: " .. app.settings.theme_preset
          save_settings()
        end
        if selected then r.ImGui_SetItemDefaultFocus(ctx) end
      end
      r.ImGui_EndCombo(ctx)
    end
    if Theme.is_reaper_theme_preset and Theme.is_reaper_theme_preset(current) then
      if r.ImGui_Button(ctx, "Refresh REAPER Theme", UIScale.text_button_w(ctx, "Refresh REAPER Theme", 160, 8), UIScale.button_h(ctx, 24)) then
        app.settings.theme_preset = Theme.set_preset(current, app.settings.custom_themes)
        app.cache.saved_theme_preset = app.settings.theme_preset
        app.status = "REAPER theme colors refreshed"
        save_settings()
      end
      if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Read colors from the active REAPER theme") end
    end
    r.ImGui_Separator(ctx)
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Preview")
    draw_theme_preview(Theme.colors)
    r.ImGui_Spacing(ctx)
    local child_visible = r.ImGui_BeginChild(ctx, "##theme_color_editor", UIScale.round(330), UIScale.round(190), 1)
    if child_visible then
      local color_flags = r.ImGui_ColorEditFlags_NoInputs()
      for _, field in ipairs(theme_color_fields) do
        local changed, value = r.ImGui_ColorEdit4(ctx, field.label .. "##" .. field.key, Theme.colors[field.key], color_flags)
        if changed then
          Theme.colors[field.key] = value
          app.settings.theme_preset = "Unsaved Custom"
          Theme.set_colors(Theme.colors, app.settings.theme_preset)
        end
      end
      r.ImGui_EndChild(ctx)
    end
    r.ImGui_TextWrapped(ctx, "Theme changes are applied immediately. Custom themes load from the preset dropdown.")
    local name_changed, new_name = r.ImGui_InputTextWithHint(ctx, "##custom_theme_name", "Custom theme name", app.settings.custom_theme_name or "My Theme")
    if name_changed then app.settings.custom_theme_name = new_name end
    local theme_name = trim_text(app.settings.custom_theme_name or "")
    local theme_exists = app.settings.custom_themes and app.settings.custom_themes[theme_name] ~= nil
    local save_label = theme_exists and "Update Custom##save_custom_theme" or "Save Custom##save_custom_theme"
    if r.ImGui_Button(ctx, save_label, 110, 24) then
      if theme_name == "" then
        app.status = "Custom theme name required"
      elseif is_reserved_theme_name(theme_name) then
        app.status = "Reserved theme names cannot be overwritten"
      else
        local existed = app.settings.custom_themes and app.settings.custom_themes[theme_name] ~= nil
        app.settings.custom_theme_name = theme_name
        app.settings.custom_themes = app.settings.custom_themes or {}
        app.settings.custom_themes[theme_name] = Theme.copy_current_colors()
        app.settings.theme_preset = theme_name
        Theme.set_preset(theme_name, app.settings.custom_themes)
        app.cache.saved_theme_preset = app.settings.theme_preset
        app.status = (existed and "Updated custom theme: " or "Saved custom theme: ") .. theme_name
        save_settings()
      end
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, theme_exists and "Update existing custom theme" or "Save current colors as custom theme") end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Delete Custom", 110, 24) then
      if theme_name == "" then
        app.status = "Custom theme name required"
      elseif is_reserved_theme_name(theme_name) then
        app.status = "Reserved themes cannot be deleted"
      elseif app.settings.custom_themes and app.settings.custom_themes[theme_name] then
        app.settings.custom_themes[theme_name] = nil
        app.settings.custom_theme_name = theme_name
        if app.settings.theme_preset == theme_name then
          app.settings.theme_preset = Theme.set_preset("Graphite", app.settings.custom_themes)
          app.cache.saved_theme_preset = app.settings.theme_preset
        end
        app.status = "Deleted custom theme: " .. theme_name
        save_settings()
      else
        app.status = "Custom theme not found: " .. theme_name
      end
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Delete custom theme by name") end
    r.ImGui_Separator(ctx)
    if r.ImGui_Button(ctx, "Reset", UIScale.text_button_w(ctx, "Reset", 90, 8), UIScale.button_h(ctx, 24)) then
      app.settings.theme_preset = Theme.set_preset("Graphite", app.settings.custom_themes)
      app.cache.saved_theme_preset = app.settings.theme_preset
      app.status = "Theme preset reset"
      save_settings()
    end
end

local function draw_preferences_tab(label, tab_id)
  local current = app.cache.preferences_tab or "general"
  local active = current == tab_id
  local pad_x = UIScale.round(10)
  local pad_y = UIScale.round(4)
  local h = r.ImGui_GetTextLineHeight(ctx) + pad_y * 2
  local w = calc_text_width(label) + pad_x * 2
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local clicked = r.ImGui_InvisibleButton(ctx, "##pref_tab_" .. tab_id, w, h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local bg = active and Theme.colors.accent_soft or (hovered and Theme.colors.frame_hover or Theme.colors.frame_bg)
  local border = active and Theme.colors.accent or Theme.colors.border
  local text_color = active and Theme.colors.accent or Theme.colors.text
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + w, y + h, bg, UIScale.px(4))
  r.ImGui_DrawList_AddRect(draw_list, x, y, x + w, y + h, border, UIScale.px(4), 0, UIScale.px(1))
  r.ImGui_DrawList_AddText(draw_list, x + pad_x, y + pad_y, text_color, label)
  if clicked then app.cache.preferences_tab = tab_id end
end

local function draw_preferences_settings()
  if app.settings_panel == "preferences" then
    app.cache.preferences_open = true
    app.settings_panel = nil
  elseif app.settings_panel == "theme" then
    app.cache.preferences_open = true
    app.cache.preferences_tab = "theme"
    app.settings_panel = nil
  end
  if not app.cache.preferences_open then return end
  local visible, open = r.ImGui_Begin(ctx, "Preferences##tk_workbench_preferences", true, r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_NoCollapse() | r.ImGui_WindowFlags_AlwaysAutoResize())
  app.cache.preferences_open = open
  if visible then
    r.ImGui_TextColored(ctx, Theme.colors.accent, "Preferences")
    local close_size = UIScale.round(14)
    r.ImGui_SameLine(ctx, math.max(UIScale.round(140), r.ImGui_GetWindowWidth(ctx) - close_size - UIScale.round(16)))
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local close_x, close_y = r.ImGui_GetCursorScreenPos(ctx)
    r.ImGui_DrawList_AddCircleFilled(draw_list, close_x + close_size * 0.5, close_y + close_size * 0.5, close_size * 0.5, 0xF7768EFF)
    r.ImGui_DrawList_AddCircle(draw_list, close_x + close_size * 0.5, close_y + close_size * 0.5, close_size * 0.5, 0x3A1018FF, 16, UIScale.px(1))
    if r.ImGui_InvisibleButton(ctx, "##preferences_close", close_size, close_size) then app.cache.preferences_open = false end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Close") end
    r.ImGui_Separator(ctx)
    local pref_tabs = { { id = "general", label = "General" }, { id = "modules", label = "Modules" }, { id = "theme", label = "Theme" } }
    for index, tab in ipairs(pref_tabs) do
      draw_preferences_tab(tab.label, tab.id)
      if index < #pref_tabs then r.ImGui_SameLine(ctx, 0, UIScale.gap(6)) end
    end
    r.ImGui_Separator(ctx)
    local active_tab = app.cache.preferences_tab or "general"
    if active_tab ~= app.cache.preferences_tab_applied then
      if active_tab == "theme" and Theme.is_reaper_theme_preset and Theme.is_reaper_theme_preset(app.settings.theme_preset) then
        Theme.set_preset(app.settings.theme_preset, app.settings.custom_themes)
      end
      app.cache.preferences_tab_applied = active_tab
    end
    if active_tab == "theme" then
      draw_theme_settings_body()
      r.ImGui_End(ctx)
      return
    end
    if active_tab == "modules" then
      r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Show or hide modules in the tiles and dropdown.")
      if r.ImGui_SmallButton(ctx, "Show all") then
        set_all_modules_hidden(false)
        app.status = "All modules visible"
      end
      r.ImGui_SameLine(ctx, 0, UIScale.gap(6))
      if r.ImGui_SmallButton(ctx, "Hide all") then
        set_all_modules_hidden(true)
        app.status = "All modules hidden"
      end
      r.ImGui_Separator(ctx)
      for _, module in ipairs(app.modules) do
        local module_visible = not is_module_hidden(module.id)
        local changed, value = r.ImGui_Checkbox(ctx, (module.title or module.id) .. "##pref_module_" .. module.id, module_visible)
        if changed then
          set_module_hidden(module.id, not value)
          app.status = value and ((module.title or module.id) .. " shown") or ((module.title or module.id) .. " hidden")
        end
      end
      r.ImGui_End(ctx)
      return
    end
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "UI scale")
    r.ImGui_PushItemWidth(ctx, 140)
    local current_scale = set_ui_scale(app.settings.ui_scale or 1.0)
    if r.ImGui_BeginCombo(ctx, "##workbench_ui_scale", ui_scale_label(current_scale)) then
      for _, option in ipairs(ui_scale_options) do
        local selected = math.abs(current_scale - option.value) < 0.01
        if r.ImGui_Selectable(ctx, option.label, selected) then
          set_ui_scale(option.value)
          app.cache.ui_fonts = {}
          app.status = "UI scale: " .. option.label
          save_settings()
        end
        if selected then r.ImGui_SetItemDefaultFocus(ctx) end
      end
      r.ImGui_EndCombo(ctx)
    end
    r.ImGui_PopItemWidth(ctx)
    r.ImGui_Separator(ctx)
    r.ImGui_PushItemWidth(ctx, UIScale.round(160))
    local alpha_pct = math.floor((app.settings.window_bg_alpha or 1.0) * 100 + 0.5)
    local alpha_changed, alpha_value = r.ImGui_SliderInt(ctx, "Background opacity", alpha_pct, 20, 100, "%d%%")
    if alpha_changed then
      app.settings.window_bg_alpha = math.max(0.2, math.min(1.0, alpha_value / 100))
      app.status = string.format("Background opacity: %d%%", alpha_value)
      save_settings()
    end
    r.ImGui_PopItemWidth(ctx)
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Lowers the main panel background opacity (floating window).")
    r.ImGui_PushItemWidth(ctx, UIScale.round(160))
    local child_pct = math.floor((app.settings.child_bg_alpha or 1.0) * 100 + 0.5)
    local child_changed, child_value = r.ImGui_SliderInt(ctx, "Module panel opacity", child_pct, 20, 100, "%d%%")
    if child_changed then
      app.settings.child_bg_alpha = math.max(0.2, math.min(1.0, child_value / 100))
      app.status = string.format("Module panel opacity: %d%%", child_value)
      save_settings()
    end
    r.ImGui_PopItemWidth(ctx)
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Lowers the module panel background opacity.")
    r.ImGui_Separator(ctx)
    local changed, value = r.ImGui_Checkbox(ctx, "Hide scrollbars", app.settings.hide_scrollbars == true)
    if changed then
      app.settings.hide_scrollbars = value
      app.status = value and "Scrollbars hidden" or "Scrollbars visible"
      save_settings()
    end
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Scroll wheel remains active.")
    r.ImGui_Separator(ctx)
    changed, value = r.ImGui_Checkbox(ctx, "Info box", app.settings.show_status ~= false)
    if changed then
      app.settings.show_status = value
      app.status = value and "Info box visible" or "Info box hidden"
      save_settings()
    end
    r.ImGui_Separator(ctx)
    changed, value = r.ImGui_Checkbox(ctx, "Module rail", app.settings.sidebar_enabled == true)
    if changed then
      app.settings.sidebar_enabled = value
      app.status = value and "Module rail shown" or "Module rail hidden"
      save_settings()
    end
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "A slim strip of module icons along the window edge (name on hover).")
    do
      local rail_side = app.settings.sidebar_side == "right" and "Right" or "Left"
      local rail_disabled = app.settings.sidebar_enabled ~= true
      if rail_disabled and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx, true) end
      r.ImGui_PushItemWidth(ctx, 140)
      if r.ImGui_BeginCombo(ctx, "Rail side", rail_side) then
        if r.ImGui_Selectable(ctx, "Left", rail_side == "Left") then
          app.settings.sidebar_side = "left"; app.status = "Module rail: left"; save_settings()
        end
        if r.ImGui_Selectable(ctx, "Right", rail_side == "Right") then
          app.settings.sidebar_side = "right"; app.status = "Module rail: right"; save_settings()
        end
        r.ImGui_EndCombo(ctx)
      end
      r.ImGui_PopItemWidth(ctx)
      if rail_disabled and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
    end
    r.ImGui_Separator(ctx)
    local auto_collapse_locked = app.cache.window_docked == true
    local auto_collapse_disabled_stack = auto_collapse_locked and r.ImGui_BeginDisabled and r.ImGui_EndDisabled
    if auto_collapse_disabled_stack then r.ImGui_BeginDisabled(ctx, true) end
    changed, value = r.ImGui_Checkbox(ctx, "Auto-collapse", app.settings.auto_collapse == true)
    if changed and not auto_collapse_locked then
      app.settings.auto_collapse = value
      app.cache.auto_collapse_collapsed = false
      app.cache.auto_collapse_force_restore = true
      app.status = value and "Auto-collapse enabled" or "Auto-collapse disabled"
      save_settings()
    end
    local side = app.settings.auto_collapse_side == "right" and "Right" or "Left"
    r.ImGui_PushItemWidth(ctx, 140)
    if r.ImGui_BeginCombo(ctx, "Lock side", side) then
      if r.ImGui_Selectable(ctx, "Left", side == "Left") and not auto_collapse_locked then
        app.settings.auto_collapse_side = "left"
        app.cache.auto_collapse_force_restore = true
        app.status = "Auto-collapse lock: left"
        save_settings()
      end
      if r.ImGui_Selectable(ctx, "Right", side == "Right") and not auto_collapse_locked then
        app.settings.auto_collapse_side = "right"
        app.cache.auto_collapse_force_restore = true
        app.status = "Auto-collapse lock: right"
        save_settings()
      end
      r.ImGui_EndCombo(ctx)
    end
    r.ImGui_PopItemWidth(ctx)
    r.ImGui_PushItemWidth(ctx, 140)
    changed, value = r.ImGui_SliderInt(ctx, "Edge offset", math.floor((tonumber(app.settings.auto_collapse_edge_offset) or 0) + 0.5), 0, 96, "%d px")
    if changed and not auto_collapse_locked then
      app.settings.auto_collapse_edge_offset = value
      app.cache.auto_collapse_force_restore = true
      app.status = "Auto-collapse edge offset: " .. tostring(value) .. " px"
      save_settings()
    end
    r.ImGui_PopItemWidth(ctx)
    r.ImGui_PushItemWidth(ctx, 140)
    changed, value = r.ImGui_SliderDouble(ctx, "Close delay", tonumber(app.settings.auto_collapse_delay) or 0.6, 0.1, 5.0, "%.1f s")
    if changed and not auto_collapse_locked then
      app.settings.auto_collapse_delay = value
      app.cache.auto_collapse_last_hover_time = r.time_precise and r.time_precise() or os.clock()
      app.status = "Auto-collapse close delay: " .. string.format("%.1f", value) .. " s"
      save_settings()
    end
    r.ImGui_PopItemWidth(ctx)
    local height_mode = app.settings.auto_collapse_height_mode
    local height_label = "Manual"
    if height_mode == "arrange" then height_label = "Arrange" end
    if height_mode == "reaper" then height_label = "REAPER window" end
    if height_mode == "arrange_window" then height_label = "Arrange to bottom" end
    r.ImGui_PushItemWidth(ctx, 140)
    if r.ImGui_BeginCombo(ctx, "Auto height", height_label) then
      if r.ImGui_Selectable(ctx, "Manual", height_label == "Manual") and not auto_collapse_locked then
        app.settings.auto_collapse_height_mode = "manual"
        app.cache.auto_collapse_force_restore = true
        app.status = "Auto height: manual"
        save_settings()
      end
      if r.ImGui_Selectable(ctx, "Arrange", height_label == "Arrange") and not auto_collapse_locked then
        app.settings.auto_collapse_height_mode = "arrange"
        app.cache.auto_collapse_force_restore = true
        app.status = "Auto height: arrange"
        save_settings()
      end
      if r.ImGui_Selectable(ctx, "REAPER window", height_label == "REAPER window") and not auto_collapse_locked then
        app.settings.auto_collapse_height_mode = "reaper"
        app.cache.auto_collapse_force_restore = true
        app.status = "Auto height: REAPER window"
        save_settings()
      end
      if r.ImGui_Selectable(ctx, "Arrange to bottom", height_label == "Arrange to bottom") and not auto_collapse_locked then
        app.settings.auto_collapse_height_mode = "arrange_window"
        app.cache.auto_collapse_force_restore = true
        app.status = "Auto height: arrange to bottom"
        save_settings()
      end
      r.ImGui_EndCombo(ctx)
    end
    r.ImGui_PopItemWidth(ctx)
    if auto_collapse_disabled_stack then r.ImGui_EndDisabled(ctx) end
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, auto_collapse_locked and "Auto-collapse is inactive while Workbench is docked." or "Floating Workbench windows only.")
    r.ImGui_Separator(ctx)
    changed, value = r.ImGui_Checkbox(ctx, "Tooltips", app.settings.tooltips_enabled ~= false)
    if changed then
      app.settings.tooltips_enabled = value
      app.cache.tooltip = nil
      app.status = value and "Tooltips enabled" or "Tooltips disabled"
      save_settings()
    end
    local delays = {
      { label = "Direct", value = 0 },
      { label = "0.5 seconds", value = 0.5 },
      { label = "1 second", value = 1.0 },
      { label = "2 seconds", value = 2.0 },
      { label = "3 seconds", value = 3.0 }
    }
    local current_delay = tonumber(app.settings.tooltip_delay) or 1.0
    local current_label = "1 second"
    for _, option in ipairs(delays) do
      if math.abs(current_delay - option.value) < 0.01 then current_label = option.label; break end
    end
    r.ImGui_PushItemWidth(ctx, 140)
    if r.ImGui_BeginCombo(ctx, "Tooltip delay", current_label) then
      for _, option in ipairs(delays) do
        local selected = math.abs(current_delay - option.value) < 0.01
        if r.ImGui_Selectable(ctx, option.label, selected) then
          app.settings.tooltip_delay = option.value
          app.cache.tooltip = nil
          app.status = option.value <= 0 and "Tooltips show directly" or ("Tooltip delay: " .. option.label)
          save_settings()
        end
        if selected then r.ImGui_SetItemDefaultFocus(ctx) end
      end
      r.ImGui_EndCombo(ctx)
    end
    r.ImGui_PopItemWidth(ctx)
  end
  r.ImGui_End(ctx)
end

local function current_time()
  return r.time_precise and r.time_precise() or os.clock()
end
local function auto_collapse_side()
  return app.settings.auto_collapse_side == "right" and "right" or "left"
end

local function auto_collapse_width()
  return clamp(app.settings.auto_collapse_width or 1, 1, 1)
end

local function auto_collapse_delay()
  return clamp(app.settings.auto_collapse_delay or 0.6, 0.1, 5.0)
end

local function auto_collapse_edge_hover_margin()
  return clamp(app.settings.auto_collapse_edge_hover_margin or 12, 0, 32)
end

local function auto_collapse_edge_offset()
  return clamp(app.settings.auto_collapse_edge_offset or 0, 0, 96)
end

local function expanded_window_min_size()
  return UIScale.round(260), UIScale.round(240)
end

local function auto_collapse_height_mode()
  local mode = app.settings.auto_collapse_height_mode
  if mode == "arrange" or mode == "reaper" or mode == "arrange_window" then return mode end
  return "manual"
end

local function auto_collapse_target_rect(mode)
  if not r.GetMainHwnd then return nil end
  local hwnd = r.GetMainHwnd()
  if not hwnd then return nil end
  local ok, left, top, right, bottom
  if mode == "arrange" then
    if not r.JS_Window_FindChildByID or not r.JS_Window_GetRect then return nil end
    local arrange = r.JS_Window_FindChildByID(hwnd, 0x3E8)
    if not arrange then return nil end
    ok, left, top, right, bottom = r.JS_Window_GetRect(arrange)
  elseif mode == "arrange_window" then
    if not r.JS_Window_FindChildByID or not r.JS_Window_GetRect then return nil end
    local arrange = r.JS_Window_FindChildByID(hwnd, 0x3E8)
    if not arrange then return nil end
    local arrange_ok, arrange_left, arrange_top, arrange_right = r.JS_Window_GetRect(arrange)
    local reaper_ok, _, _, reaper_right, reaper_bottom
    if r.JS_Window_GetClientRect then reaper_ok, _, _, reaper_right, reaper_bottom = r.JS_Window_GetClientRect(hwnd) end
    if not reaper_ok and r.JS_Window_GetRect then reaper_ok, _, _, reaper_right, reaper_bottom = r.JS_Window_GetRect(hwnd) end
    if not arrange_ok or not reaper_ok then return nil end
    ok = true
    left = arrange_left
    top = arrange_top
    right = reaper_right or arrange_right
    bottom = reaper_bottom
  elseif mode == "reaper" then
    if r.JS_Window_GetClientRect then ok, left, top, right, bottom = r.JS_Window_GetClientRect(hwnd) end
    if not ok and r.JS_Window_GetRect then ok, left, top, right, bottom = r.JS_Window_GetRect(hwnd) end
  else
    return nil
  end
  if not ok then return nil end
  left = tonumber(left)
  top = tonumber(top)
  right = tonumber(right)
  bottom = tonumber(bottom)
  if not left or not top or not right or not bottom then return nil end
  return left, top, right, bottom
end

local function auto_collapse_height_bounds()
  local mode = auto_collapse_height_mode()
  if mode == "manual" then return nil end
  local left, top, right, bottom = auto_collapse_target_rect(mode)
  if not left then return nil end
  if r.ImGui_PointConvertNative then
    local _, converted_top = r.ImGui_PointConvertNative(ctx, left, top)
    local _, converted_bottom = r.ImGui_PointConvertNative(ctx, right, bottom)
    top = tonumber(converted_top) or top
    bottom = tonumber(converted_bottom) or bottom
  end
  if bottom <= top then return nil end
  return top, bottom - top
end

local function auto_collapse_available()
  return app.settings.auto_collapse == true and app.cache.window_docked == false
end

local function auto_collapse_reaper_edge(side)
  if not r.GetMainHwnd then return nil end
  local hwnd = r.GetMainHwnd()
  if not hwnd then return nil end
  local ok, left, _, right
  if r.JS_Window_GetClientRect then ok, left, _, right = r.JS_Window_GetClientRect(hwnd) end
  if not ok and r.JS_Window_GetRect then ok, left, _, right = r.JS_Window_GetRect(hwnd) end
  if not ok then return nil end
  left = tonumber(left)
  right = tonumber(right)
  if not left or not right then return nil end
  if side == "right" then return right end
  return left
end

local function auto_collapse_native_edge(side)
  local reaper_edge = auto_collapse_reaper_edge(side)
  if reaper_edge then return reaper_edge end
  if not r.ImGui_GetMainViewport or not r.ImGui_Viewport_GetWorkPos or not r.ImGui_Viewport_GetWorkSize then return nil end
  local viewport = r.ImGui_GetMainViewport(ctx)
  if not viewport then return nil end
  local work_x = r.ImGui_Viewport_GetWorkPos(viewport)
  local work_w = r.ImGui_Viewport_GetWorkSize(viewport)
  work_x = tonumber(work_x)
  work_w = tonumber(work_w)
  if not work_x or not work_w then return nil end
  if side == "right" then return work_x + work_w end
  return work_x
end

local function auto_collapse_viewport_edge(side)
  local reaper_edge = auto_collapse_reaper_edge(side)
  if reaper_edge then
    if r.ImGui_PointConvertNative then
      local converted = r.ImGui_PointConvertNative(ctx, reaper_edge, 0)
      converted = tonumber(converted)
      if converted then return converted end
    end
    return reaper_edge
  end
  if not r.ImGui_GetMainViewport or not r.ImGui_Viewport_GetWorkPos or not r.ImGui_Viewport_GetWorkSize then return nil end
  local viewport = r.ImGui_GetMainViewport(ctx)
  if not viewport then return nil end
  local work_x = r.ImGui_Viewport_GetWorkPos(viewport)
  local work_w = r.ImGui_Viewport_GetWorkSize(viewport)
  work_x = tonumber(work_x)
  work_w = tonumber(work_w)
  if not work_x or not work_w then return nil end
  if side == "right" then return work_x + work_w end
  return work_x
end

local function auto_collapse_mouse_on_outer_edge()
  if not r.GetMousePosition then return false end
  local side = auto_collapse_side()
  local edge = auto_collapse_native_edge(side)
  if not edge then return false end
  local mouse_x = r.GetMousePosition()
  mouse_x = tonumber(mouse_x)
  if not mouse_x then return false end
  if not app.cache.auto_collapse_collapsed then
    if side == "right" then return mouse_x >= edge end
    return mouse_x <= edge
  end
  local margin = auto_collapse_edge_hover_margin()
  if side == "right" then return mouse_x >= edge and mouse_x <= edge + margin end
  return mouse_x <= edge and mouse_x >= edge - margin
end

local function auto_collapse_keep_open()
  if app.settings.auto_collapse_keep_expanded == true then return true end
  if auto_collapse_mouse_on_outer_edge() then return true end
  if app.cache.preferences_open or app.settings_panel then return true end
  if r.ImGui_IsPopupOpen and r.ImGui_PopupFlags_AnyPopupId then
    local ok, any_popup = pcall(r.ImGui_IsPopupOpen, ctx, "", r.ImGui_PopupFlags_AnyPopupId())
    if ok and any_popup then return true end
  end
  if r.ImGui_IsWindowHovered and r.ImGui_HoveredFlags_AnyWindow then
    local flags = r.ImGui_HoveredFlags_AnyWindow()
    if r.ImGui_HoveredFlags_AllowWhenBlockedByActiveItem then flags = flags | r.ImGui_HoveredFlags_AllowWhenBlockedByActiveItem() end
    if r.ImGui_IsWindowHovered(ctx, flags) then return true end
  end
  for _, module in ipairs(app.modules or {}) do
    if module.keep_workbench_expanded then
      local ok, keep = pcall(module.keep_workbench_expanded, app)
      if ok and keep then return true end
    end
  end
  if r.ImGui_IsAnyItemActive and r.ImGui_IsAnyItemActive(ctx) then return true end
  return false
end

local function apply_auto_collapse_window()
  local available = auto_collapse_available()
  if not available then
    app.cache.auto_collapse_collapsed = false
    app.cache.auto_collapse_force_restore = nil
    -- The floor under the window size used to be part of auto-collapse and went
    -- away with it, so a window with auto-collapse off could be dragged shut
    -- entirely. It belongs to the window, not to that feature.
    if r.ImGui_SetNextWindowSizeConstraints then
      local min_w, min_h = expanded_window_min_size()
      r.ImGui_SetNextWindowSizeConstraints(ctx, min_w, min_h, 100000, 100000)
    end
    return
  end
  local collapsed = app.cache.auto_collapse_collapsed == true
  local force_restore = app.cache.auto_collapse_force_restore == true
  local min_w, min_h = expanded_window_min_size()
  local expanded_w = math.max(min_w, app.cache.auto_collapse_expanded_w or app.cache.window_w or app.settings.window_width or 430)
  local expanded_h = math.max(min_h, app.cache.auto_collapse_expanded_h or app.cache.window_h or app.settings.window_height or 760)
  local auto_top, auto_h = auto_collapse_height_bounds()
  if auto_h then expanded_h = math.max(min_h, auto_h) end
  local target_w = collapsed and auto_collapse_width() or expanded_w
  local target_h = expanded_h
  local cond_always = r.ImGui_Cond_Always and r.ImGui_Cond_Always() or 0
  if r.ImGui_SetNextWindowSizeConstraints then
    if collapsed then
      r.ImGui_SetNextWindowSizeConstraints(ctx, target_w, target_h, target_w, target_h)
    else
      r.ImGui_SetNextWindowSizeConstraints(ctx, min_w, min_h, 100000, 100000)
    end
  end
  if (collapsed or force_restore or auto_h) and r.ImGui_SetNextWindowSize then r.ImGui_SetNextWindowSize(ctx, target_w, target_h, cond_always) end
  if r.ImGui_SetNextWindowPos then
    local side = auto_collapse_side()
    local edge = auto_collapse_viewport_edge(side)
    if not edge and side == "right" and app.cache.window_x and app.cache.window_w then edge = app.cache.window_x + app.cache.window_w end
    if not edge and side == "left" and app.cache.window_x then edge = app.cache.window_x end
    if edge then
      local offset = collapsed and 0 or auto_collapse_edge_offset()
      local target_x = side == "right" and (edge - target_w - offset) or (edge + offset)
      r.ImGui_SetNextWindowPos(ctx, target_x, auto_top or app.cache.window_y or 0, cond_always)
    end
  end
  if force_restore and not collapsed then app.cache.auto_collapse_force_restore = nil end
end

local function save_expanded_window_size(docked)
  if docked or app.cache.auto_collapse_collapsed then return end
  local min_w, min_h = expanded_window_min_size()
  local width = math.floor(math.max(min_w, app.cache.window_w or app.settings.window_width or 430) + 0.5)
  local height = math.floor(math.max(min_h, app.cache.window_h or app.settings.window_height or 760) + 0.5)
  if math.abs(width - (tonumber(app.settings.window_width) or 0)) < 2 and math.abs(height - (tonumber(app.settings.window_height) or 0)) < 2 then return end
  app.settings.window_width = width
  app.settings.window_height = height
  local now = current_time()
  if now - (app.cache.window_size_last_save or 0) >= 0.75 then
    app.cache.window_size_last_save = now
    save_settings()
  else
    app.cache.window_size_dirty = true
  end
end

local function flush_window_size_if_dirty()
  if app.cache.window_size_dirty then
    app.cache.window_size_dirty = nil
    app.cache.window_size_last_save = current_time()
    save_settings()
  end
end

local function draw_auto_collapse_strip()
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetWindowPos(ctx)
  local w, h = r.ImGui_GetWindowSize(ctx)
  local side = auto_collapse_side()
  local border_x = side == "right" and x or (x + w)
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  r.ImGui_InvisibleButton(ctx, "##auto_collapse_handle", math.max(1, w), math.max(1, h))
  local hovered = r.ImGui_IsItemHovered(ctx)
  if hovered then
    r.ImGui_DrawList_AddLine(draw_list, border_x, y, border_x, y + h, Theme.colors.accent, 1)
    r.ImGui_SetTooltip(ctx, "Expand Workbench")
  end
end

local function push_auto_collapse_style()
  local vars = 0
  local colors = 0
  if app.cache.auto_collapse_collapsed and r.ImGui_StyleVar_WindowMinSize then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowMinSize(), 1, 1)
    vars = vars + 1
  end
  if app.cache.auto_collapse_collapsed and r.ImGui_StyleVar_WindowPadding then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, 0)
    vars = vars + 1
  end
  if app.cache.auto_collapse_collapsed and r.ImGui_StyleVar_WindowBorderSize then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowBorderSize(), 0)
    vars = vars + 1
  end
  if app.cache.auto_collapse_collapsed and r.ImGui_PushStyleColor and r.ImGui_Col_WindowBg then
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), 0x00000000)
    colors = colors + 1
  end
  if app.cache.auto_collapse_collapsed and r.ImGui_PushStyleColor and r.ImGui_Col_Border then
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), 0x00000000)
    colors = colors + 1
  end
  return vars, colors
end

local function pop_auto_collapse_style(vars, colors)
  if colors and colors > 0 then r.ImGui_PopStyleColor(ctx, colors) end
  if vars and vars > 0 then r.ImGui_PopStyleVar(ctx, vars) end
end

local function update_auto_collapse_state(window_hovered, docked)
  app.cache.window_docked = docked == true
  if app.settings.auto_collapse ~= true or docked then
    app.cache.auto_collapse_collapsed = false
    app.cache.auto_collapse_force_restore = nil
    app.cache.auto_collapse_last_hover_time = current_time()
    return
  end
  local now = current_time()
  local keep_open = window_hovered or auto_collapse_keep_open()
  if keep_open then
    app.cache.auto_collapse_last_hover_time = now
    if app.cache.auto_collapse_collapsed then
      app.cache.auto_collapse_collapsed = false
      app.cache.auto_collapse_force_restore = true
    end
    return
  end
  local last_hover = app.cache.auto_collapse_last_hover_time or now
  app.cache.auto_collapse_last_hover_time = last_hover
  if not app.cache.auto_collapse_collapsed and now - last_hover >= auto_collapse_delay() then
    local min_w, min_h = expanded_window_min_size()
    app.cache.auto_collapse_expanded_w = math.max(min_w, app.cache.window_w or app.settings.window_width or 430)
    app.cache.auto_collapse_expanded_h = math.max(min_h, app.cache.window_h or app.settings.window_height or 760)
    app.cache.auto_collapse_collapsed = true
  end
end

local function workbench_window_hovered()
  if not r.ImGui_IsWindowHovered then return false end
  local flags = 0
  if r.ImGui_HoveredFlags_RootAndChildWindows then flags = flags | r.ImGui_HoveredFlags_RootAndChildWindows() end
  if r.ImGui_HoveredFlags_AllowWhenBlockedByActiveItem then flags = flags | r.ImGui_HoveredFlags_AllowWhenBlockedByActiveItem() end
  return r.ImGui_IsWindowHovered(ctx, flags)
end

local function push_workspace_style()
  local vars = 0
  if app.settings.hide_scrollbars and r.ImGui_StyleVar_ScrollbarSize then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ScrollbarSize(), 0)
    vars = vars + 1
  end
  return vars
end

local function pop_workspace_style(vars)
  if vars and vars > 0 then r.ImGui_PopStyleVar(ctx, vars) end
end

local function draw_module_error(module, err)
  -- An ImGui structural failure (an unbalanced PushID or BeginChild inside a
  -- module) invalidates the context on its way out. Drawing the message on that
  -- dead context would raise a second, more confusing error and hide the real
  -- one, so bail out here: loop() recreates the context on the next frame and
  -- the message shows up then.
  if r.ImGui_ValidatePtr and not r.ImGui_ValidatePtr(ctx, "ImGui_Context*") then return end
  local width = r.ImGui_GetContentRegionAvail(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local pad = UIScale.round(10)
  local height = math.max(UIScale.round(72), math.ceil(r.ImGui_GetTextLineHeight(ctx) * 4.2))
  local bg = Theme.colors.frame_bg
  local warning_text = Theme.text_for_background(bg, Theme.colors.warning, nil, 4.5)
  local detail_text = Theme.text_for_background(bg, Theme.colors.text_dim, Theme.colors.text, 4.5)
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, bg, UIScale.px(5))
  r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + height, Theme.colors.warning, UIScale.px(5), 0, UIScale.px(1))
  r.ImGui_SetCursorScreenPos(ctx, x + pad, y + UIScale.round(8))
  r.ImGui_TextColored(ctx, warning_text, tostring(module and (module.title or module.id) or "Module") .. " error")
  r.ImGui_SetCursorScreenPos(ctx, x + pad, y + UIScale.round(30))
  r.ImGui_PushTextWrapPos(ctx, x + width - pad)
  r.ImGui_TextColored(ctx, detail_text, tostring(err))
  r.ImGui_PopTextWrapPos(ctx)
  r.ImGui_SetCursorScreenPos(ctx, x, y + height + UIScale.round(6))
  r.ImGui_Dummy(ctx, 1, 1)
end

local function draw_module_instance(module, pane_id)
  if not module then
    r.ImGui_TextColored(ctx, Theme.text_for_backgrounds({ Theme.colors.window_bg, Theme.colors.child_bg }, Theme.colors.warning, nil, 4.5), "No modules loaded")
    return
  end
  r.ImGui_PushID(ctx, pane_id or module.id)
  if module.draw then
    -- Cleared first, so a note left by whatever drew before this cannot be read
    -- as belonging to this module's failure.
    app.breadcrumb = nil
    local ok, err = pcall(module.draw, app)
    if ok then
      clear_module_error(module.id .. ".draw")
    else
      record_module_error(module.id .. ".draw", err)
      draw_module_error(module, err)
    end
    -- Deliberately not cleared here. The PopID below is outside the module's own
    -- pcall, so when that is the thing that fails the note has to survive long
    -- enough to be read - and that failure is exactly the one we are chasing.
  end
  r.ImGui_PopID(ctx)
end

local function splitter_thickness()
  return UIScale.round(14)
end

local function cycle_split_pin()
  local pin = app.settings.split_pinned_pane
  local next_pin = ""
  if pin ~= "primary" and pin ~= "secondary" then
    next_pin = "primary"
  elseif pin == "primary" then
    next_pin = "secondary"
  end
  app.settings.split_pinned_pane = next_pin
  app.settings.split_pinned_return = ""
  if next_pin == "" then
    app.status = "Pane unpinned"
  else
    app.status = "Pinned the " .. pane_label(next_pin) .. " pane - modules now open in the other one"
  end
  save_settings()
end

-- The pin lives on the splitter rather than in a pane. A pane is a child window
-- and modules fill it with child windows of their own, which take the mouse and
-- draw over anything the pane itself put there - so a pin in the corner was both
-- unreliable to click and easy to lose behind module content. The splitter
-- belongs to the workbench, and nothing is ever on top of it.
local function draw_split_pin(size)
  local pin = app.settings.split_pinned_pane
  local pinned = pin == "primary" or pin == "secondary"
  local clicked = r.ImGui_InvisibleButton(ctx, "##tk_workbench_split_pin", size, size)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local x1, y1 = r.ImGui_GetItemRectMin(ctx)
  local x2, y2 = r.ImGui_GetItemRectMax(ctx)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local color = Theme.colors.text_dim
  if pinned then
    color = Theme.colors.accent
  elseif hovered then
    color = Theme.colors.text
  end
  if pinned or hovered then
    r.ImGui_DrawList_AddRectFilled(draw_list, x1, y1, x2, y2, Theme.colors.frame_bg, UIScale.px(3))
  end
  -- Which side is being kept is said by the accent edge along the splitter, not
  -- by this glyph. At this size one clear shape reads and two do not.
  draw_pin_icon(draw_list, (x1 + x2) * 0.5, (y1 + y2) * 0.5, size * 0.66, color, pinned)
  if hovered then
    local other = pane_label(pin == "primary" and "secondary" or "primary")
    if pin == "primary" then
      r.ImGui_SetTooltip(ctx, "Keeping the " .. pane_label("primary") .. " pane\nModules you open go to the " .. other .. " pane\nClick: keep the " .. other .. " pane instead")
    elseif pin == "secondary" then
      r.ImGui_SetTooltip(ctx, "Keeping the " .. pane_label("secondary") .. " pane\nModules you open go to the " .. other .. " pane\nClick: keep neither")
    else
      r.ImGui_SetTooltip(ctx, "Keep a pane\nA kept pane holds on to its module and everything you open lands in the other one\nClick: keep the " .. pane_label("primary") .. " pane")
    end
  end
  if clicked then cycle_split_pin() end
end

local function draw_splitter(total, orientation)
  local horizontal = orientation == "horizontal"
  local avail_w, avail_h = r.ImGui_GetContentRegionAvail(ctx)
  local thickness = splitter_thickness()
  local gap = UIScale.round(2)
  -- The pin takes a square off one end and the drag zone gets the rest, so the
  -- two never overlap and a click is only ever one of them. Item spacing goes to
  -- zero for the duration: the gap is the explicit one below, and the automatic
  -- spacing on top of it would push the group past the room the split gave it.
  local spacing_pushed = false
  if r.ImGui_PushStyleVar and r.ImGui_StyleVar_ItemSpacing then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 0, 0)
    spacing_pushed = true
  end
  r.ImGui_BeginGroup(ctx)
  if horizontal then
    draw_split_pin(thickness)
    r.ImGui_Dummy(ctx, thickness, gap)
  end
  local width = horizontal and thickness or math.max(UIScale.round(20), (avail_w or 0) - thickness - gap)
  local height = horizontal and math.max(UIScale.round(20), (avail_h or 0) - thickness - gap) or thickness
  r.ImGui_InvisibleButton(ctx, "##workbench_splitter", width, height)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local active = r.ImGui_IsItemActive(ctx)
  if active and r.ImGui_GetMouseDragDelta then
    local drag_x, drag_y = r.ImGui_GetMouseDragDelta(ctx, 0, 0)
    local delta = horizontal and (drag_x or 0) or (drag_y or 0)
    if math.abs(delta) > 0 then
      app.settings.split_ratio = clamp((tonumber(app.settings.split_ratio) or 0.5) + delta / math.max(1, total), 0.18, 0.82)
      app.cache.split_ratio_dirty = true
      if r.ImGui_ResetMouseDragDelta then r.ImGui_ResetMouseDragDelta(ctx, 0) end
    end
  elseif app.cache.split_ratio_dirty then
    app.cache.split_ratio_dirty = nil
    save_settings()
  end
  local x1, y1 = r.ImGui_GetItemRectMin(ctx)
  local x2, y2 = r.ImGui_GetItemRectMax(ctx)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local background = Theme.colors.child_bg or Theme.colors.window_bg or 0x181818FF
  local rail_color = contrast_from_background(background, hovered and 0.16 or 0.11)
  local grip_color = active and Theme.colors.accent or contrast_from_background(background, hovered and 0.34 or 0.24)
  if horizontal then
    r.ImGui_DrawList_AddRectFilled(draw_list, x1 + 1, y1, x2 - 1, y2, rail_color, 3)
    r.ImGui_DrawList_AddRectFilled(draw_list, x1 + 3, y1 + 8, x2 - 3, y2 - 8, grip_color, 2)
  else
    r.ImGui_DrawList_AddRectFilled(draw_list, x1, y1 + 1, x2, y2 - 1, rail_color, 3)
    r.ImGui_DrawList_AddRectFilled(draw_list, x1 + 8, y1 + 3, x2 - 8, y2 - 3, grip_color, 2)
  end
  -- The kept pane gets an accent edge down the side of the splitter facing it,
  -- running the whole length. That is what says which pane is held; the pin
  -- itself only says whether one is.
  local pin = app.settings.split_pinned_pane
  if pin == "primary" or pin == "secondary" then
    local edge = UIScale.px(2)
    local first = pin == "primary"
    if horizontal then
      local ex = first and x1 or (x2 - edge)
      r.ImGui_DrawList_AddRectFilled(draw_list, ex, y1, ex + edge, y2, Theme.colors.accent, 1)
    else
      local ey = first and y1 or (y2 - edge)
      r.ImGui_DrawList_AddRectFilled(draw_list, x1, ey, x2, ey + edge, Theme.colors.accent, 1)
    end
  end
  if hovered or active then r.ImGui_SetTooltip(ctx, "Drag to resize split") end
  if not horizontal then
    r.ImGui_SameLine(ctx, 0, gap)
    draw_split_pin(thickness)
  end
  r.ImGui_EndGroup(ctx)
  if spacing_pushed then r.ImGui_PopStyleVar(ctx) end
end

local function draw_split_pane(module, slot, width, height, pane_flags)
  local visible = r.ImGui_BeginChild(ctx, "##workbench_split_" .. slot, width, height, 0, pane_flags)
  if visible then
    draw_module_instance(module, slot)
    r.ImGui_EndChild(ctx)
  end
end

local function draw_module_canvas()
  if is_home_active() then
    draw_home_view()
    return
  end
  local module = get_active_module()
  if not split_view_available() then
    draw_module_instance(module, "primary")
    return
  end
  local split_module = get_split_module()
  local available_w, available_h = r.ImGui_GetContentRegionAvail(ctx)
  local horizontal = split_orientation() == "horizontal"
  local splitter_size = splitter_thickness()
  local pane_flags = 0
  if r.ImGui_WindowFlags_NoScrollbar then pane_flags = pane_flags | r.ImGui_WindowFlags_NoScrollbar() end
  if r.ImGui_WindowFlags_NoScrollWithMouse then pane_flags = pane_flags | r.ImGui_WindowFlags_NoScrollWithMouse() end
  local ratio = clamp(tonumber(app.settings.split_ratio) or 0.5, 0.18, 0.82)
  if horizontal then
    local total_w = math.max(40, available_w or 240)
    local spacing_x = 7
    if r.ImGui_GetStyleVar and r.ImGui_StyleVar_ItemSpacing then
      local sx = r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing())
      spacing_x = tonumber(sx) or spacing_x
    end
    local content_w = math.max(20, total_w - splitter_size - spacing_x * 2)
    local min_w = math.min(UIScale.round(220), math.floor(content_w * 0.45))
    local left_w = clamp(math.floor(content_w * ratio), min_w, math.max(min_w, content_w - min_w))
    local right_w = math.max(20, content_w - left_w)
    draw_split_pane(module, "primary", left_w, 0, pane_flags)
    r.ImGui_SameLine(ctx, 0, 0)
    draw_splitter(content_w, "horizontal")
    r.ImGui_SameLine(ctx, 0, 0)
    draw_split_pane(split_module, "secondary", right_w, 0, pane_flags)
    return
  end
  local total_h = math.max(40, available_h or 240)
  local spacing_y = 7
  if r.ImGui_GetStyleVar and r.ImGui_StyleVar_ItemSpacing then
    local _, current_spacing_y = r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing())
    spacing_y = tonumber(current_spacing_y) or spacing_y
  end
  local content_h = math.max(20, total_h - splitter_size - spacing_y * 2)
  local min_h = math.min(100, math.floor(content_h * 0.45))
  local top_h = math.floor(content_h * ratio)
  top_h = clamp(top_h, min_h, math.max(min_h, content_h - min_h))
  local bottom_h = math.max(20, content_h - top_h)
  draw_split_pane(module, "primary", 0, top_h, pane_flags)
  draw_splitter(content_h, "vertical")
  draw_split_pane(split_module, "secondary", 0, bottom_h, pane_flags)
end

local function module_rail_width()
  return UIScale.round(54)
end

-- A slim, always-visible strip of icon-only module tiles along the window edge.
-- Reuses the same icon art and click behaviour as the Home grid / dropdown.
local function draw_module_rail()
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local rail_left = app.settings.sidebar_side ~= "right"
  local pad_outer = UIScale.round(0)
  local pad_inner = UIScale.round(10)
  local avail_w = r.ImGui_GetContentRegionAvail(ctx) or UIScale.round(40)
  -- Bias the tiles toward the outer edge (small outer margin, larger gap to the
  -- inner divider). Indent lives on the left, so it flips with the rail side.
  local tile = math.max(UIScale.round(20), avail_w - pad_outer - pad_inner)
  local inset = UIScale.round(7)
  local left_indent = rail_left and pad_outer or pad_inner
  r.ImGui_Dummy(ctx, 1, pad_outer)
  -- Guard against Indent(0): ImGui treats a 0 argument as the default IndentSpacing
  -- (~21px), which shoved the left-rail tiles off-centre.
  if left_indent > 0 then r.ImGui_Indent(ctx, left_indent) end

  local function tile_button(key, is_active, tooltip, on_activate, paint, on_context)
    r.ImGui_PushID(ctx, key)
    local clicked = r.ImGui_InvisibleButton(ctx, "##rail_tile", tile, tile)
    local hovered = r.ImGui_IsItemHovered(ctx)
    local right_clicked = on_context and r.ImGui_IsItemClicked and r.ImGui_IsItemClicked(ctx, 1)
    local x1, y1 = r.ImGui_GetItemRectMin(ctx)
    local x2, y2 = r.ImGui_GetItemRectMax(ctx)
    local bg = is_active and Theme.colors.accent_soft or (hovered and Theme.colors.frame_hover or Theme.colors.frame_bg)
    local border = (is_active or hovered) and Theme.colors.accent or Theme.colors.border
    local icon_color = Theme.text_for_background(bg, (hovered or is_active) and Theme.colors.accent or Theme.colors.text_dim, nil, 3)
    r.ImGui_DrawList_AddRectFilled(draw_list, x1, y1, x2, y2, bg, UIScale.px(5))
    r.ImGui_DrawList_AddRect(draw_list, x1, y1, x2, y2, border, UIScale.px(5), 0, is_active and UIScale.px(1.6) or UIScale.px(0.8))
    paint(x1, y1, x2, y2, icon_color)
    if hovered and tooltip then r.ImGui_SetTooltip(ctx, tooltip) end
    if clicked then on_activate() end
    if right_clicked then on_context() end
    r.ImGui_PopID(ctx)
  end

  for _, module in ipairs(app.modules) do
    if not is_module_hidden(module.id) then
      local mod = module
      local tip = tostring(mod.title or mod.id) .. "\nRight-click: show in split view"
      tile_button(mod.id, app.settings.active_module == mod.id, tip,
        function() if mod.on_click then mod.on_click() else set_active_view(mod.id) end end,
        function(x1, y1, x2, y2, color)
          draw_module_icon(draw_list, mod, (x1 + x2) * 0.5, (y1 + y2) * 0.5, tile - inset * 2, color)
        end,
        function() set_split_module(mod.id) end)
    end
  end

  if horizontal_rack_entry_visible() then
    tile_button("__hrack", false, tostring(HORIZONTAL_RACK_ENTRY.title),
      function() open_horizontal_rack() end,
      function(x1, y1, x2, y2, color)
        draw_module_icon(draw_list, HORIZONTAL_RACK_ENTRY, (x1 + x2) * 0.5, (y1 + y2) * 0.5, tile - inset * 2, color)
      end)
  end

  if left_indent > 0 then r.ImGui_Unindent(ctx, left_indent) end
end

local function visible_module_error_ids()
  local result = {}
  if is_home_active() then return result end
  local active = get_active_module()
  if active then result[active.id] = true end
  if split_view_available() then
    local split_module = get_split_module()
    if split_module then result[split_module.id] = true end
  end
  return result
end

local function module_error_status()
  local visible = visible_module_error_ids()
  for key, err in pairs(app.module_errors) do
    local module_id, phase = tostring(key):match("^(.-)%.(.+)$")
    module_id = module_id or tostring(key)
    phase = phase or "module"
    if phase ~= "draw" or visible[module_id] then return key, err end
  end
  return nil
end

local function module_error_text(key)
  local module_id, phase = tostring(key):match("^(.-)%.(.+)$")
  module_id = module_id or tostring(key)
  phase = phase or "module"
  local module = app.modules_by_id[module_id]
  local title = tostring(module and (module.title or module.id) or module_id)
  return title .. " " .. phase .. " error"
end

local function draw_status_bar()
  local selection = app.selection or {}
  local captured = UI.get_captured_info_line(app)
  local text = captured and tostring(captured.text or "") or (app.status or "Ready")
  local captured_options = captured and captured.options or {}
  local details = ""
  local severity = captured_options.severity or "info"
  if captured_options.details then details = tostring(captured_options.details) end
  if selection.track and selection.track.name then text = text .. " | Track: " .. selection.track.name end
  if selection.item and selection.item.take_name then text = text .. " | Take: " .. selection.item.take_name end
  local key, err = module_error_status()
  if key then
    text = module_error_text(key)
    details = tostring(err) .. "\n\nLogged to workbench_errors.txt."
    severity = "error"
  end
  UI.draw_info_line(ctx, text, { severity = severity, details = details, force = true })
end

local function update_modules()
  for _, module in ipairs(app.modules) do
    if module.update then
      local ok, err = pcall(module.update, app)
      if ok then clear_module_error(module.id .. ".update") else record_module_error(module.id .. ".update", err) end
    end
  end
end

local function shutdown()
  if app.cache.shutdown_done then return end
  app.cache.shutdown_done = true
  r.SetExtState(MODULE_ACTION_EXT_SECTION, MODULE_ACTION_RUNNING_KEY, "false", false)
  r.SetExtState(MODULE_ACTION_EXT_SECTION, MODULE_ACTION_HEARTBEAT_KEY, "", false)
  for _, module in ipairs(app.modules) do
    if module.shutdown then pcall(module.shutdown, app) end
  end
  if app.settings.theme_preset == "Unsaved Custom" then
    app.settings.theme_preset = app.cache.saved_theme_preset or "Graphite"
  end
  save_settings()
end

if r.atexit then r.atexit(shutdown) end

local function draw_shell()
  draw_top_bar()
  local status_h = app.settings.show_status and UI.info_line_height(ctx, true) or 0
  local avail_w, available_h = r.ImGui_GetContentRegionAvail(ctx)
  local canvas_h = math.max(40, (available_h or 240) - status_h)
  local canvas_flags = 0
  if r.ImGui_WindowFlags_NoScrollbar then canvas_flags = canvas_flags | r.ImGui_WindowFlags_NoScrollbar() end
  if r.ImGui_WindowFlags_NoScrollWithMouse then canvas_flags = canvas_flags | r.ImGui_WindowFlags_NoScrollWithMouse() end
  app.cache.captured_info_line = nil

  local rail_enabled = app.settings.sidebar_enabled == true
  local rail_w = rail_enabled and module_rail_width() or 0
  local rail_left = app.settings.sidebar_side ~= "right"
  local spacing = UIScale.gap(4)
  local rail_flags = 0
  if r.ImGui_WindowFlags_NoScrollbar then rail_flags = rail_flags | r.ImGui_WindowFlags_NoScrollbar() end
  local shell_draw_list = r.ImGui_GetWindowDrawList(ctx)
  local shell_origin_x, shell_origin_y = r.ImGui_GetCursorScreenPos(ctx)

  local function draw_rail_pane()
    if r.ImGui_PushStyleVar and r.ImGui_StyleVar_WindowPadding then
      r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), UIScale.round(4), UIScale.round(4))
    end
    local visible = r.ImGui_BeginChild(ctx, "##workbench_module_rail", rail_w, canvas_h, 0, rail_flags)
    if visible then
      draw_module_rail()
      r.ImGui_EndChild(ctx)
    end
    if r.ImGui_PopStyleVar and r.ImGui_StyleVar_WindowPadding then r.ImGui_PopStyleVar(ctx, 1) end
  end

  local function draw_canvas_pane(width)
    local child_visible = r.ImGui_BeginChild(ctx, "##workbench_module_canvas", width, canvas_h, 0, canvas_flags)
    if child_visible then
      UI.begin_info_line_capture(app)
      draw_module_canvas()
      UI.end_info_line_capture(app)
      r.ImGui_Dummy(ctx, 1, 1)
      r.ImGui_EndChild(ctx)
    end
  end

  if rail_enabled and rail_left then
    draw_rail_pane()
    r.ImGui_SameLine(ctx, 0, spacing)
    draw_canvas_pane(0)
  elseif rail_enabled then
    local canvas_w = math.max(40, (avail_w or 240) - rail_w - spacing)
    draw_canvas_pane(canvas_w)
    r.ImGui_SameLine(ctx, 0, spacing)
    draw_rail_pane()
  else
    draw_canvas_pane(0)
  end

  if rail_enabled then
    -- Divider sits on the rail band's inner edge, so tile->divider spacing equals
    -- the tile->outer-edge window padding on the other side of the strip.
    local sep_x = rail_left and (shell_origin_x + rail_w)
      or (shell_origin_x + (avail_w or 0) - rail_w)
    sep_x = math.floor(sep_x) + 0.5
    r.ImGui_DrawList_AddLine(shell_draw_list, sep_x, shell_origin_y, sep_x, shell_origin_y + canvas_h, Theme.colors.border, UIScale.px(1))
  end

  if app.settings.show_status then draw_status_bar() end
end

local MISSING_EXT_DISMISS_SECTION = "TK_WORKBENCH"
local MISSING_EXT_DISMISS_KEY = "missing_ext_dismissed"

local function collect_missing_extensions()
  local list = {}
  if not r.TK_StartFileDrag then
    list[#list + 1] = {
      title = "TK Native Helper",
      package = "reaper_tk_native_helper",
      desc = "Lets the Media Browser drop samples straight onto external plugin windows.",
    }
  end
  if r.GetExtState("TK_WORKBENCH_ACTION_CAPTURE", "available") ~= "true" then
    list[#list + 1] = {
      title = "TK Action Capture",
      package = "reaper_tk_action_capture",
      desc = "Captures REAPER actions so the Action Clipboard can record them.",
    }
  end
  return list
end

local function missing_ext_signature(list)
  local names = {}
  for _, entry in ipairs(list) do names[#names + 1] = entry.package end
  table.sort(names)
  return table.concat(names, "|")
end

local function draw_missing_extensions_popup()
  if not app.cache.missing_ext_open then return end
  local list = app.missing_extensions
  if not list or #list == 0 then app.cache.missing_ext_open = false return end
  r.ImGui_SetNextWindowSize(ctx, UIScale.round(440), 0, r.ImGui_Cond_Appearing())
  local visible, open = r.ImGui_Begin(ctx, "Missing extensions##tk_workbench_missing_ext", true, r.ImGui_WindowFlags_NoCollapse() | r.ImGui_WindowFlags_AlwaysAutoResize())
  app.cache.missing_ext_open = open
  if visible then
    r.ImGui_TextColored(ctx, Theme.colors.warning, "Some native extensions are not installed")
    r.ImGui_Separator(ctx)
    r.ImGui_TextWrapped(ctx, "Install the packages below via ReaPack (Extensions category) and restart REAPER to enable the related features.")
    r.ImGui_Dummy(ctx, 1, UIScale.round(6))
    for _, entry in ipairs(list) do
      r.ImGui_TextColored(ctx, Theme.colors.accent, entry.title)
      r.ImGui_SameLine(ctx, 0, UIScale.gap(6))
      r.ImGui_TextColored(ctx, Theme.colors.text_dim, "(" .. entry.package .. ")")
      r.ImGui_TextWrapped(ctx, entry.desc)
      r.ImGui_Dummy(ctx, 1, UIScale.round(6))
    end
    r.ImGui_Separator(ctx)
    local changed, dont_show = r.ImGui_Checkbox(ctx, "Don't show this again", app.cache.missing_ext_dismiss == true)
    if changed then app.cache.missing_ext_dismiss = dont_show end
    if r.ImGui_Button(ctx, "Close", UIScale.round(120), 0) then
      if app.cache.missing_ext_dismiss then
        r.SetExtState(MISSING_EXT_DISMISS_SECTION, MISSING_EXT_DISMISS_KEY, missing_ext_signature(list), true)
      end
      app.cache.missing_ext_open = false
    end
  end
  r.ImGui_End(ctx)
end

local function draw_frame()
  if r.ImGui_ValidatePtr and not r.ImGui_ValidatePtr(ctx, "ImGui_Context*") then
    ctx = r.ImGui_CreateContext(SCRIPT_NAME)
    app.ctx = ctx
    app.cache.tooltip = nil
    app.cache.ui_fonts = {}
    app.cache.ui_font_ctx = nil
  end
  set_ui_scale(app.settings.ui_scale or 1.0)
  -- Scanned after the modules have had their update, not before. A module's
  -- update is where the blocking work happens - the Project Browser opens a
  -- project there - and opening one frees every item and track in the old one.
  -- Snapshotting first left the pointers dangling for the drawing that follows,
  -- and a module reading one of them throws from inside its pcall, which leaves
  -- the id stack crooked and takes the next EndChild down with it.
  update_modules()
  app.selection = Selection.scan()
  r.SetExtState(MODULE_ACTION_EXT_SECTION, MODULE_ACTION_RUNNING_KEY, "true", false)
  r.SetExtState(MODULE_ACTION_EXT_SECTION, MODULE_ACTION_HEARTBEAT_KEY, tostring(r.time_precise and r.time_precise() or os.clock()), false)
  process_module_action_commands()
  UI.begin_tooltip_frame(app)
  r.ImGui_SetNextWindowSize(ctx, app.settings.window_width or 430, app.settings.window_height or 760, r.ImGui_Cond_FirstUseEver())
  apply_auto_collapse_window()
  if (app.settings.theme_preset or "Graphite") ~= Theme.current_preset then
    app.settings.theme_preset = Theme.set_preset(app.settings.theme_preset or "Graphite", app.settings.custom_themes)
  end
  local scaled_font_pushed = push_scaled_font()
  local theme_stack = Theme.push(ctx, app.settings.child_bg_alpha or 1.0)
  local workspace_style_vars = push_workspace_style()
  local auto_collapse_style_vars, auto_collapse_style_colors = push_auto_collapse_style()
  local window_flags = r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
  if r.ImGui_WindowFlags_NoFocusOnAppearing then
    window_flags = window_flags | r.ImGui_WindowFlags_NoFocusOnAppearing()
  end
  if app.settings.auto_collapse == true and app.cache.window_docked == false and r.ImGui_WindowFlags_NoMove then
    window_flags = window_flags | r.ImGui_WindowFlags_NoMove()
  end
  if r.ImGui_SetNextWindowBgAlpha then
    r.ImGui_SetNextWindowBgAlpha(ctx, app.settings.window_bg_alpha or 1.0)
  end
  local visible, open = r.ImGui_Begin(ctx, SCRIPT_NAME, true, window_flags)
  if visible then
    app.cache.window_x, app.cache.window_y = r.ImGui_GetWindowPos(ctx)
    app.cache.window_w, app.cache.window_h = r.ImGui_GetWindowSize(ctx)
    local docked = r.ImGui_IsWindowDocked and r.ImGui_IsWindowDocked(ctx) or false
    if app.cache.auto_collapse_collapsed and not docked then
      draw_auto_collapse_strip()
    else
      if app.settings.auto_collapse == true and not docked then
        local min_w, min_h = expanded_window_min_size()
        app.cache.auto_collapse_expanded_w = math.max(min_w, app.cache.window_w or app.settings.window_width or 430)
        app.cache.auto_collapse_expanded_h = math.max(min_h, app.cache.window_h or app.settings.window_height or 760)
      end
      draw_shell()
    end
    save_expanded_window_size(docked)
    update_auto_collapse_state(workbench_window_hovered(), docked)
  end
  r.ImGui_End(ctx)
  draw_preferences_settings()
  draw_missing_extensions_popup()
  UI.end_tooltip_frame(app)
  pop_auto_collapse_style(auto_collapse_style_vars, auto_collapse_style_colors)
  pop_workspace_style(workspace_style_vars)
  Theme.pop(ctx, theme_stack)
  pop_scaled_font(scaled_font_pushed)
  flush_window_size_if_dirty()
  return open
end

-- An ImGui structural failure inside a module (an unbalanced PushID or
-- BeginChild) invalidates the context on its way out, and every later call in
-- that frame then fails too -- including the ones that were meant to clean up.
-- Without this guard the very first of those errors ends the defer chain and
-- takes the whole window down. Catching it here costs one dropped frame:
-- draw_frame recreates the context at the top of the next one and carries on.
local function loop()
  local ok, result = pcall(draw_frame)
  if not ok then
    record_module_error("workbench.frame", result)
    result = true -- keep going; the next frame starts from a fresh context
  end
  if result and not app.close_requested then
    r.defer(loop)
  else
    shutdown()
  end
end

ModuleLoader.load(app, module_names)
apply_module_order()
if app.settings.active_module ~= HOME_MODULE_ID and not app.modules_by_id[app.settings.active_module] and app.modules[1] then
  app.settings.active_module = app.modules[1].id
  save_settings()
end

app.missing_extensions = collect_missing_extensions()
if #app.missing_extensions > 0 and r.GetExtState(MISSING_EXT_DISMISS_SECTION, MISSING_EXT_DISMISS_KEY) ~= missing_ext_signature(app.missing_extensions) then
  app.cache.missing_ext_open = true
end

r.defer(loop)