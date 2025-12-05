-- @description TK ChordGun - Enhanced chord generator with scale filter/remap and chord recognition
-- @author TouristKiller (based on pandabot ChordGun)
-- @version 2.3.7
-- @changelog
--[[
2.3.7
+ Slot Settings Dropdown: Click [+] button on progression slots to open settings panel
+ Direct arrow controls for Beats, Repeats, Octave, and Inversion
+ Dropdown appears below the slot, over other content
+ Click outside dropdown or [+] again to close
+ Original slot appearance preserved

2.3.6
+ Progression Templates: 70+ preset progressions (Right-click Load button)
+ 10 Genre categories: Pop/Rock, Jazz, Blues, Classical, Modal, Minor Keys, EDM, World/Folk
+ Mode-aware templates: Auto-adapts chord qualities to current scale
+ Scale validation: Templates filtered by minimum required notes
+ Safety fix: No more crash when switching scales during progression playback

2.3.4 
+ Theme bugfix

2.3.3
+ Custom MIDI Trigger Mapping: Assign any MIDI note to any chord button (Right-click chord)
+ Column Mode: Trigger entire scale degree columns with single MIDI notes (Right-click trigger button > Mode)
+ Built-in Preset: "White Keys (C2-B2)" for quick Column Mode setup
+ Preset System: Save/Load your custom trigger mappings to ChordMaps folder
+ Visual Indicators: Yellow squares show mapped triggers (top-left for chords, top-right for columns)
+ Harmonic Compass Redesign: Colored squares in bottom-right corner (replaces border highlight)
+ Persistent Settings: Harmonic Compass state now saved between sessions
+ Trigger notes are automatically filtered from chord recognition
+ Preset Display: Current trigger preset name shown in chord display area
+ 6 Color Themes: Dark, Light, Color, Neon, Ocean, Mono (click Theme button to cycle)

2.3.2
+ Fixed Window Size/Position not being remembered for some users (Now saves globally instead of per-project)
+ Fixed Window Size resetting to default if resized smaller than initial minimum
+ Fixed MIDI Trigger Legato behavior (Now correctly falls back to held notes on release)
+ Fixed MIDI Trigger stopping melody notes (Now only stops script-generated notes)

2.3.1
+ Added "Harmonic Compass" (Smart Suggestions): Highlights logical next chords based on functional harmony
+ Added "Use Selected Chord Types" option to Randomize (Surprise Me) feature (Right-click Dice)
+ Added Extended Chord Vocabulary (9th, 11th, 13th, 6/9, etc.)
+ Added "Filter" Dropdown to control chord visibility (Basic, Standard, Jazz)
+ Added "All" modes to Filter Dropdown (Std All, Jazz All) to show non-scale chords
+ Replaced "In Scale" toggle with the new Filter Dropdown

2.3.0
+ Added Right-Click Context Menu on Chord Buttons
+ Added "Generate Leading Chords" feature (Right-click > Add ii-V-I)
+ Added "Tritone Substitution" feature (Right-click > Add ii-bII-I)
+ Added "Insert to MIDI" option for generated leading chords (Direct insertion)
+ Added "Add to Progression" option for generated leading chords (Append to slots)
+ Fixed JSFX Scale Filter syntax error and added Monitor slider
+ Fixed "Hold" button behavior (now correctly latches notes)
+ Fixed JSFX button color in Light Theme (now Blue when active)
+ Fixed crash when inserting generated chords without a selected MIDI item (Auto-creates item)

2.2.9
+ Added MIDI Trigger Mode: Trigger chords via MIDI keyboard (C1-B1 range)
+ Added Channel 16 Bypass: Prevents script-generated chords from being distorted by Remap Mode
+ Added Extended Trigger Mapping: Black keys (C#1-A#1) now trigger scale degrees 8-12 (for Messiaen/10-note scales)
+ Added "Surprise Me" (Randomize) Dice button to fill empty slots with random chords (weighted I, IV, V, vi)
+ Added Randomize Settings (Right-click Dice): Progression Length (4/8), Always Start on Tonic, Clear Progression
+ Added Sync button to sync ChordGun scale with MIDI Editor key snap
+ Added Fifth Wheel scaling (window size now saves/restores)
+ Fixed issue with Fifth Wheel window not closing properly
+ Added "Selection" length option. Time selection is now ONLY used when this option is active.
+ Improved Workflow: Smart item selection/creation. Keeps items selected for continuous insertion, but allows creating new items by clicking outside existing ones.
+ Improved Track Selection: Prioritizes Selected Track, then Last Touched Track.
+ Improved Melody Generator: Uses active track or asks to create new one (no longer sticky)
+ Fixed crash when playing a progression with empty slots (e.g. empty slot 1). Empty slots are now skipped/silent.
+ Added Sync Play: Right-click Play button to toggle. Syncs script playback with Reaper transport (Play/Stop).
+ Improved Playback Timing: Sync Play now prioritizes audio over UI updates for tighter timing.
+ Added longer note lengths (2 bars, 4 bars, 8 bars)
+ Changed Note Length selector to a Dropdown menu for easier selection
+ Renamed "Selection" to "Time Selection" for clarity
+ Added Per-slot Inversion/Octave storage: Alt+Click now saves the current Octave and Inversion to the progression slot.
+ Added Hold Slot behavior: Clicking a progression slot now plays the chord as long as the mouse is held down (unless playback is running).


2.2.1 /2.2.6
+ Bug fixes

2.2.0
+ Added Automatic Voice Leading ("Lead" button) for smooth chord transitions
+ Added Arpeggiator (Arp) mode with adjustable patterns (Up, Down, Up/Down, Random)
+ Added Arp speed control (Milliseconds or Grid Sync: 1/4, 1/8, 1/16, etc.)
+ Added Score View (Staff notation) to the Circle of Fifths window
+ Added Guitar View (Fretboard) to the Circle of Fifths window
+ Extended Keyboard Shortcuts to 10 keys (0, ), p, ;, /)
+ Added Spacebar shortcut to stop all notes
+ Improved Piano Display to show actual played notes (including inversions/voicings)
+ Improved UI layout (Chord Text Label position and color)
+ Added missing 7th chords
+ Added Light Theme support
+ Improved Dark Theme visibility for new views
+ Updated Chromatic View style
+ General layout improvements
+ Fixed "ghost notes" bug in Voice Leading

2.1.6
+ Fixed Messiaen Modes data (corrected note counts and patterns for Modes 1, 2, 3, and 7)
+ Improved Messiaen Mode 1 (added 2nd transposition)
+ Improved Messiaen Mode 2 (corrected transposition order)
+ Improved Messiaen Mode 3 (corrected binary patterns)
+ Improved Messiaen Mode 7 (corrected note count to 10)
+ Fixed User Reascales loading on startup
+ Improved Reascale parser (supports digits 2-9 as active notes)
+ Improved UI scaling for dropdown menus

2.1.5
+ Added "Drop 2" and "Drop 3" voicings for 4-note chords (Jazz/Neo-Soul style)
+ Replaced "Bass" button with "Voicing" button (Menu: Off, Drop 2, Drop 3, Bass -1, Bass -2)
+ Added "Linear View" to Circle of Fifths window (Piano-roll style interval visualization)

2.1.4
+ Fixed UI layout overlap caused by new chord type (Piano keyboard now positioned correctly below 14th chord row)
+ Increased base window height to accommodate extra chord row

2.1.2
+ Added "Minor-Major 7th" chord type (minMaj7) - Essential for Harmonic/Melodic Minor scales
+ Smart Initial Scaling: Window size now adapts to screen height on first run (prevents oversized window on small screens)

2.1.1
+ Added JSFX check and auto-install prompt when enabling Filter/Remap modes

2.1.0
+ Added "Chromatic" view to Circle of Fifths window (visualizes symmetry of Messiaen modes)
+ Added "Equivalent Tonic" indicators (Halo rings) in Chromatic view to show limited transpositions
+ Added Interval Pattern display to chord tooltips (shows steps and cumulative intervals for Messiaen modes)
+ Added Power Chord (C5) recognition (supports 2-note chords)
+ Added Melody Generator: Create random melodies based on chord progression (Melody button)
+ Added Melody Settings (Right-click Melody button): Rhythm Density, Octave Range, Note Selection
+ Improved Export to Chord Track: Pins track to top, locks height/items, adds to bottom of project
+ Improved Presets: Now saves/loads Scale Tonic and Scale Type with the progression
+ Added "Export to Project Regions" (Right-click Insert button)
+ Added support for running script from Main section (Arrange View) without active MIDI Editor
+ Added automatic MIDI item creation if no item is selected when inserting chords
+ Added Font Scale menu options (Small=1.0, Normal=1.25, Big=1.5, Bigger=1.75)
+ Added "Ratio" menu options (fixed ratio between width and height for non-distorted scaling)
+ Fixed Inversion logic (prevented compounding inversions)
+ Fixed MIDI Input sorting (chronological order for better chord detection)
+ Fixed Melody Generator dissonance (weighted probability for scale notes)
+ Added "Bass" feature: Add root note 1 or 2 octaves lower (Cycle button: Off, -1, -2)
+ UI improvements: Reorganized bottom row buttons, polished Chromatic View (dots), restored Fifths View Legend
+ UI improvements (Right-side button layout, dynamic Chord Display width)

2.0.3 
+ Fixed bug where scale pattern could be nil during chord recognition, causing crashes (mini)

2.0.0
+ Added comprehensive scale library with 87 scales across 7 systems
+ Two-level dropdown system: Scale System → Scale Type
+ Scale systems: Diatonic (11), Pentatonic (6), Messiaen (32), Jazz (10), World Music (12), Blues & Soul (8), Rock & Metal (8)
+ Educational tooltips for all scales (description + interval patterns)
+ World Music: Arabic/Middle Eastern (Hijaz, Persian, Double Harmonic), Japanese (Hirajoshi, In Sen, Iwato), Indian Ragas (Bhairav, Kafi), Hungarian/Gypsy scales
+ Jazz: Bebop family (4 variants), Modern jazz (Altered, Lydian Dominant, Melodic Minor), Symmetrical diminished scales
+ Blues & Soul: Blues scales (Major/Minor/Classic), Mixo-Blues, Gospel scales, Soul scale, Dominant Blues
+ Rock & Metal: Harmonic Minor, Phrygian Dominant, Neapolitan (Minor/Major), Hungarian Major, Super Locrian, Lydian #2, Aeolian b5
+ Expanded Messiaen from 8 to 32 modes (all transpositions of Mode 1-7)
+ Expanded Pentatonic from 1 to 6 scales (Major, Minor, Blues, Egyptian, Japanese, Hirajoshi)
+ Circle of Fifths auto-closes when main window closes
+ ExtState persistence for both dropdown levels with backwards compatibility
+ All scale descriptions include: note count, character/mood, musical context, and usage examples

1.3.0
+ Added 8 Messiaen Modes of Limited Transposition
+ Modes 1-7.1 with 5-9 notes per scale (symmetrical structures)
+ Dynamic window width adjusts automatically (5-9 column layouts)
+ Separate X/Y scaling functions for proper aspect ratio
+ Keyboard shortcuts extended to support 9 notes (1-9, q-o, a-l, z-.)
+ Simple numeric scale degree headers (1-9) for non-tonal Messiaen modes
+ Roman numeral headers preserved for diatonic scales
+ Circle of Fifths adapts display for Messiaen modes:
  * Diatonic scales: harmonic distance color coding
  * Messiaen modes: simplified light blue coloring
+ Context-aware legend updates automatically
+ Real-time sync between scale types without closing Circle of Fifths

1.2.2
+ Some changes to circle of fifths visualization colors and layout
+ Changed pentatonic scale to better reflect common usage:
  C Pentatonic: C, D, E, G, A
  Buttons tonen: I, II, III, V, VI

1.2.0
+ Added Circle of Fifths visualization window
+ Interactive circle shows tonic and all scale notes
+ Harmonic distance color coding (rainbow spectrum)
+ Click any note to instantly change tonic
+ Relative minor display below each major note
+ Sharp/flat notation toggle button
+ Color legend with scale degree relationships
+ Brightness boost and thick borders for in-scale notes
+ Persistent window position across sessions
+ Real-time bidirectional sync with main window
+ Scalable UI matching parent window

1.1.0
+ Added Scale Filter/Remap modes (Off/Filter/Remap button)
+ Filter mode: blocks notes outside current scale
+ Remap mode: maps white piano keys to scale notes
+ Added TK_Scale_Filter.jsfx for live MIDI processing
+ Setup button: auto-installs JSFX to track's Input FX
+ Chord recognition system with 13+ chord types
+ Real-time chord display with scale-aware color coding
+ Enharmonic spelling based on scale context
+ Piano keyboard shows remap arrows in Remap mode
+ All playing notes now show in blue (unified color scheme)
+ Cross-platform compatible (Windows, macOS, Linux)

1.0.3
+ Fully resizable window with dynamic scaling
+ 8-slot chord progression system with playback
+ Save/load progression presets
+ INSERT function to add progressions as MIDI
+ PLAY/STOP progression playback with tempo sync
+ Configurable beats and repeats per slot
+ Integrated scrollable help window
+ Smart window size persistence
+ Strum mode with adjustable delay
]]--

--[[
================================================================================
TRIBUTE & ACKNOWLEDGMENTS
================================================================================

This script is based on the brilliant "ChordGun" by pandabot.

A huge thank you to pandabot for creating the original ChordGun - an incredibly
intuitive and creative MIDI chord generator. 
The core design, scale-based chord generation, and keyboard
shortcuts are all testament to pandabot's vision for making music theory accessible
and fun within REAPER.

TK modifications build upon this solid foundation by adding:
- Scale filtering and remapping for live MIDI performance
- Real-time chord recognition and analysis
- Enhanced progression workflow tools
- Improved UI flexibility and cross-platform support

The original ChordGun remains at the heart of this tool. All credit for the core
concept and brilliant UX design goes to pandabot.

Thank you, pandabot, for this amazing contribution to the REAPER community!

Original ChordGun: https://github.com/benjohnson2001/ChordGun
================================================================================
]]--

local alwaysOnTopEnabled = false
package.path = debug.getinfo(1,"S").source:match[[^@?(.*[\/])[^\/]-$]] .."?.lua;".. package.path
local Data = require("TK_ChordGun_Data")

baseWidth = 775
baseHeight = 775
syncPlayEnabled = false 

local setThemeColor 

function getDynamicBaseWidth()
  return 1090
end

local fontScale = tonumber(reaper.GetExtState("TK_ChordGun", "fontScale")) or 1.25

function fontSize(value)
  return math.floor((s(value) * fontScale) + 0.5)
end

function applyDefaultFont()

  local useMono = reaper.GetExtState("TK_ChordGun", "useMonospaceFont") ~= "0"

  if useMono then

    local os = reaper.GetOS()
    local fontName = "Courier New"
    
    if string.match(os, "Win") then
      fontName = "Consolas"
    elseif string.match(os, "OSX") or string.match(os, "macOS") then
      fontName = "Menlo"
    else
      fontName = "DejaVu Sans Mono"
    end

    gfx.setfont(1, fontName, fontSize(14), string.byte('b')) 
  else

    gfx.setfont(1, "Arial", fontSize(15))
  end
end


function sx(value)
	if gfx.w == 0 then
		return value * 2.0
	end
	local dynamicWidth = getDynamicBaseWidth()
	local scaleX = gfx.w / dynamicWidth
  return math.floor((value * scaleX) + 0.5)
end


function sy(value)
	if gfx.h == 0 then
		return value * 2.0
	end
	local scaleY = gfx.h / baseHeight
  return math.floor((value * scaleY) + 0.5)
end


function s(value)
	if gfx.w == 0 or gfx.h == 0 then
		return value * 2.0
	end
	local dynamicWidth = getDynamicBaseWidth()
	local scaleX = gfx.w / dynamicWidth
	local scaleY = gfx.h / baseHeight
	local scale = (scaleX + scaleY) / 2
  return math.floor((value * scale) + 0.5)
end

chords = Data.chords

-- NEW: Vocabulary / Visibility Logic
local chordVisibilityMode = tonumber(reaper.GetExtState("TK_ChordGun", "vocabMode")) or 2 -- 1=Basic, 2=Std, 3=Jazz

-- REMOVED: Manual injection of extended chords (now in Data file)

local function getChordVisibilityLimit()
  if chordVisibilityMode == 1 then return 7 end -- Basic (Triads)
  if chordVisibilityMode == 2 then return 15 end -- Standard (7ths)
  return 999 -- Extended
end


local pendingTooltips = {}

function queueTooltip(text, x, y)
	pendingTooltips = {text = text, x = x, y = y}
end

function renderPendingTooltips()
	if pendingTooltips.text then
		drawTooltip(pendingTooltips.text, pendingTooltips.x, pendingTooltips.y)
		pendingTooltips = {}
	end
end

dropdownBlocksInput = false

function mouseIsHoveringOver(element)
	if dropdownBlocksInput then return false end

	local x = gfx.mouse_x
	local y = gfx.mouse_y

	local isInHorizontalRegion = (x >= element.x and x < element.x+element.width)
	local isInVerticalRegion = (y >= element.y and y < element.y+element.height)
	return isInHorizontalRegion and isInVerticalRegion
end

function drawTooltip(text, x, y)

	local padding = s(6)
	local offsetX = s(12)
	local offsetY = s(12)
	

  gfx.setfont(1, "Arial", fontSize(12))
	local textWidth, textHeight = gfx.measurestr(text)
	
	local boxWidth = textWidth + padding * 2
	local boxHeight = textHeight + padding * 2
	

	local tooltipX = x + offsetX
	local tooltipY = y + offsetY
	

	if tooltipX + boxWidth > gfx.w then
		tooltipX = x - boxWidth - offsetX
	end
	if tooltipY + boxHeight > gfx.h then
		tooltipY = y - boxHeight - offsetY
	end
	

	setThemeColor("tooltipBg")
	gfx.rect(tooltipX, tooltipY, boxWidth, boxHeight, 1)
	

	setThemeColor("tooltipBorder")
	gfx.rect(tooltipX, tooltipY, boxWidth, boxHeight, 0)
	

	setThemeColor("tooltipText")
	gfx.x = tooltipX + padding
	gfx.y = tooltipY + padding
	gfx.drawstr(text)
end

function setPositionAtMouseCursor()

  gfx.x = gfx.mouse_x
  gfx.y = gfx.mouse_y
end

function leftMouseButtonIsHeldDown()
  return gfx.mouse_cap & 1 == 1
end

function leftMouseButtonIsNotHeldDown()
  return gfx.mouse_cap & 1 ~= 1
end

function rightMouseButtonIsHeldDown()
  return gfx.mouse_cap & 2 == 2
end

function clearConsoleWindow()
  reaper.ShowConsoleMsg("")
end

function print(arg)
  reaper.ShowConsoleMsg(tostring(arg) .. "\n")
end

function getScreenWidth()
	local _, _, screenWidth, _ = reaper.my_getViewport(0, 0, 0, 0, 0, 0, 0, 0, true)
	return screenWidth
end

function getScreenHeight()
	local _, _, _, screenHeight = reaper.my_getViewport(0, 0, 0, 0, 0, 0, 0, 0, true)
	return screenHeight
end

function windowIsDocked()
	return gfx.dock(-1) > 0
end

function windowIsNotDocked()
	return not windowIsDocked()
end

function notesAreSelected()

	local activeMidiEditor = reaper.MIDIEditor_GetActive()
	local activeTake = reaper.MIDIEditor_GetTake(activeMidiEditor)

	local noteIndex = 0
	local noteExists = true
	local noteIsSelected = false

	while noteExists do

		noteExists, noteIsSelected = reaper.MIDI_GetNote(activeTake, noteIndex)

		if noteIsSelected then
			return true
		end
	
		noteIndex = noteIndex + 1
	end

	return false
end

function startUndoBlock()
	reaper.Undo_BeginBlock()
end

function endUndoBlock(actionDescription)
	reaper.Undo_OnStateChange(actionDescription)
	reaper.Undo_EndBlock(actionDescription, -1)
end

function emptyFunctionToPreventAutomaticCreationOfUndoPoint()
end


local workingDirectory = reaper.GetResourcePath() .. "/Scripts/TK Scripts/Midi/TK_ChordGun"

defaultScaleTonicNoteValue = 1
defaultScaleTypeValue = 1
defaultScaleNotesTextValue = ""
defaultChordTextValue = ""
defaultSelectedScaleNote = 1
defaultOctave = 3


defaultSelectedChordTypes = {}
for i = 1, 12 do
  table.insert(defaultSelectedChordTypes, 1)
end

defaultInversionStates = {}
for i = 1, 12 do
  table.insert(defaultInversionStates, 0)
end

defaultScaleNoteNames = {'C', 'D', 'E', 'F', 'G', 'A', 'B'}
defaultScaleDegreeHeaders = {'I', 'ii', 'iii', 'IV', 'V', 'vi', 'viio'}

defaultNotesThatArePlaying = {}
defaultDockState = 0
defaultWindowShouldBeDocked = tostring(false)

local _, top, _, bottom = reaper.my_getViewport(0, 0, 0, 0, 0, 0, 0, 0, true)
local screenH = bottom - top
local maxSafeHeight = screenH * 0.85
local calculatedScale = maxSafeHeight / baseHeight

if calculatedScale > 2.0 then calculatedScale = 2.0 end
if calculatedScale < 0.75 then calculatedScale = 0.75 end

local defaultUiScale = calculatedScale
interfaceWidth = baseWidth * defaultUiScale
interfaceHeight = baseHeight * defaultUiScale

function defaultInterfaceXPosition()

  local screenWidth = getScreenWidth()
  return screenWidth/2 - interfaceWidth/2
end

function defaultInterfaceYPosition()

  local screenHeight = getScreenHeight()
  return screenHeight/2 - interfaceHeight/2
end
local Context = {
  activeProjectIndex = 0,
  sectionName = "com.touristkiller.TK_ChordGun"
}

local ConfigKeys = {
  scaleTonicNote = "scaleTonicNote",
  scaleType = "scaleType",
  scaleNotesText = "scaleNotesText",
  chordText = "chordText",
  chordInversionStates = "chordInversionStates",
  selectedScaleNote = "selectedScaleNote",
  octave = "octave",
  selectedChordTypes = "selectedChordTypes",
  scaleNoteNames = "scaleNoteNames",
  scaleDegreeHeaders = "scaleDegreeHeaders",
  notesThatArePlaying = "notesThatArePlaying",
  dockState = "dockState",
  windowShouldBeDocked = "shouldBeDocked",
  interfaceXPosition = "interfaceXPosition",
  interfaceYPosition = "interfaceYPosition",
  interfaceWidth = "interfaceWidth",
  interfaceHeight = "interfaceHeight",
  noteLengthIndex = "noteLengthIndex",
  scaleFilterEnabled = "scaleFilterEnabled",
  midiTriggerMappings = "midiTriggerMappings",
  midiTriggerColumnMappings = "midiTriggerColumnMappings",
  midiTriggerMode = "midiTriggerMode",
  showHarmonicCompass = "showHarmonicCompass"
}

function setValue(key, value)
  reaper.SetProjExtState(Context.activeProjectIndex, Context.sectionName, key, value)
end

function getValue(key, defaultValue)

  local valueExists, value = reaper.GetProjExtState(Context.activeProjectIndex, Context.sectionName, key)

  if valueExists == 0 then
    setValue(key, defaultValue)
    return tostring(defaultValue)
  end

  return value
end

local globalExtSection = "TK_ChordGun"

function setPersistentValue(key, value)
  if not reaper.SetExtState then return end
  reaper.SetExtState(globalExtSection, key, tostring(value), true)
end

function getPersistentValue(key)
  if not reaper.GetExtState then return nil end
  local saved = reaper.GetExtState(globalExtSection, key)
  if saved ~= nil and saved ~= "" then
    return saved
  end
  return nil
end

function getPersistentNumber(key, defaultValue)
  local globalValue = getPersistentValue(key)
  if globalValue ~= nil then
    return tonumber(globalValue)
  end
  return tonumber(getValue(key, defaultValue))
end

function setPersistentNumber(key, value)
  setValue(key, value)
  setPersistentValue(key, value)
end


local strumEnabled = false
local strumDelayMs = 80
local arpEnabled = false
local arpMode = 1 -- 1: Up, 2: Down, 3: Up/Down, 4: Random, 5: Down/Up
local arpSpeedMs = 200
local arpSpeedMode = "ms" -- "ms" or "grid"
local arpGrid = "1/8"

local voiceLeadingEnabled = false
local lastPlayedNotes = {}

local function getAveragePitch(notes)
    if not notes or #notes == 0 then return 0 end
    local sum = 0
    for _, note in ipairs(notes) do sum = sum + note end
    return sum / #notes
end
local showOnlyScaleChords = reaper.GetExtState("TK_ChordGun", "showOnlyScaleChords") == "1"
local chordListScrollOffset = 0
local maxVisibleRows = 12
local isLightMode = reaper.GetExtState("TK_ChordGun", "lightMode") == "1"
local themeMode = tonumber(reaper.GetExtState("TK_ChordGun", "themeMode")) or (isLightMode and 2 or 1)
local voicingState = {
  drop2 = false,
  drop3 = false,
  bass1 = false,
  bass2 = false
}


local melodySettings = {
  density = 2,
  octave = 5,
  useScaleNotes = false
}


local tooltipsEnabled = false


local scaleFilterGmemBlock = "TK_ChordGun_Filter"
local scaleFilterMode = tonumber(getValue("scaleFilterMode", "0")) or 0
local midiTriggerEnabled = false
local midiTriggerMappings = {}
local midiTriggerColumnMappings = {}
local midiTriggerMode = 1
local midiTriggerLearnTarget = nil
local midiTriggerState = {}
local activeTriggerNote = nil
local currentTriggerPreset = nil




local chordProgression = {}
local maxProgressionSlots = 8
local progressionPlaying = false
local currentProgressionIndex = 0
local currentProgressionRepeat = 0
local progressionBeatsPerChord = 1
local progressionLastBeatTime = 0
local selectedProgressionSlot = nil
local progressionLength = 8
local randomizeStartWithTonic = false
local randomizeUseSelectedChords = false
local showHarmonicCompass = (getPersistentValue(ConfigKeys.showHarmonicCompass) or "true") == "true"

local lastPlayedScaleDegree = 1
local suggestionRules = {
  -- From I
  [1] = {
    {degree=4, type="safe"},   -- IV
    {degree=5, type="safe"},   -- V
    {degree=6, type="safe"},   -- vi
    {degree=2, type="spicy"},  -- ii
    {degree=3, type="spicy"}   -- iii
  },
  -- From ii
  [2] = {
    {degree=5, type="strong"}, -- V (Circle of Fifths)
    {degree=4, type="safe"},   -- IV
    {degree=6, type="spicy"}   -- vi
  },
  -- From iii
  [3] = {
    {degree=6, type="strong"}, -- vi (Circle of Fifths)
    {degree=4, type="safe"}    -- IV
  },
  -- From IV
  [4] = {
    {degree=1, type="strong"}, -- I (Plagal)
    {degree=5, type="safe"},   -- V
    {degree=2, type="safe"}    -- ii
  },
  -- From V
  [5] = {
    {degree=1, type="strong"}, -- I (Perfect)
    {degree=6, type="spicy"},  -- vi (Deceptive)
    {degree=4, type="safe"}    -- IV
  },
  -- From vi
  [6] = {
    {degree=2, type="strong"}, -- ii (Circle of Fifths)
    {degree=4, type="safe"},   -- IV
    {degree=5, type="safe"},   -- V
    {degree=3, type="spicy"}   -- iii
  },
  -- From vii
  [7] = {
    {degree=1, type="strong"}, -- I (Resolution)
    {degree=3, type="safe"}    -- iii
  }
}

function getSuggestionType(scaleNoteIndex)
  if not lastPlayedScaleDegree then return nil end
  local suggestions = suggestionRules[lastPlayedScaleDegree]
  if not suggestions then return nil end
  for _, item in ipairs(suggestions) do
    if item.degree == scaleNoteIndex then return item.type end
  end
  return nil
end

local pruneInternalNoteEvents
local registerInternalNoteEvent
local consumeInternalNoteEvent
local isExternalDevice
local suppressExternalMidiUntil = 0

function getTableFromString(arg)

  local output = {}

  for match in arg:gmatch("([^,%s]+)") do
    output[#output + 1] = match
  end

  return output
end

function updateScaleFilterState()
  if not reaper.gmem_attach or not reaper.gmem_write then return end
  if not reaper.gmem_attach(scaleFilterGmemBlock) then return end
  reaper.gmem_write(0, scaleFilterMode)
  for i = 0, 11 do
    local noteIndex = i + 1
    local allowed = (scalePattern and scalePattern[noteIndex]) and 1 or 0
    reaper.gmem_write(1 + i, allowed)
  end
  reaper.gmem_write(20, midiTriggerEnabled and 1 or 0)
  for i = 0, 127 do
    local shouldBlock = false
    if midiTriggerEnabled then
      if midiTriggerMode == 1 and midiTriggerMappings[i] then
        shouldBlock = true
      elseif midiTriggerMode == 2 and midiTriggerColumnMappings[i] then
        shouldBlock = true
      end
    end
    reaper.gmem_write(32 + i, shouldBlock and 1 or 0)
  end
end

function loadMidiTriggerMappings()
  local json = getPersistentValue(ConfigKeys.midiTriggerMappings) or "{}"
  midiTriggerMappings = {}
  for noteStr, s, c in json:gmatch('"(%d+)":%s*{%s*"s":%s*(%d+)%s*,%s*"c":%s*(%d+)%s*}') do
    local note = tonumber(noteStr)
    midiTriggerMappings[note] = {scaleNoteIndex = tonumber(s), chordTypeIndex = tonumber(c)}
  end
  
  local jsonCol = getPersistentValue(ConfigKeys.midiTriggerColumnMappings) or "{}"
  midiTriggerColumnMappings = {}
  for noteStr, col in jsonCol:gmatch('"(%d+)":%s*(%d+)') do
    local note = tonumber(noteStr)
    midiTriggerColumnMappings[note] = tonumber(col)
  end
  
  midiTriggerMode = tonumber(getPersistentValue(ConfigKeys.midiTriggerMode)) or 1
end

function saveMidiTriggerMappings()
  local parts = {}
  for note, data in pairs(midiTriggerMappings) do
    table.insert(parts, string.format('"%d":{"s":%d,"c":%d}', note, data.scaleNoteIndex, data.chordTypeIndex))
  end
  local json = "{" .. table.concat(parts, ",") .. "}"
  setPersistentValue(ConfigKeys.midiTriggerMappings, json)
  
  local colParts = {}
  for note, col in pairs(midiTriggerColumnMappings) do
    table.insert(colParts, string.format('"%d":%d', note, col))
  end
  local jsonCol = "{" .. table.concat(colParts, ",") .. "}"
  setPersistentValue(ConfigKeys.midiTriggerColumnMappings, jsonCol)
  
  setPersistentValue(ConfigKeys.midiTriggerMode, tostring(midiTriggerMode))
end

function setMidiTriggerMapping(midiNote, scaleNoteIndex, chordTypeIndex)
  for existingNote, data in pairs(midiTriggerMappings) do
    if data.scaleNoteIndex == scaleNoteIndex and data.chordTypeIndex == chordTypeIndex then
      midiTriggerMappings[existingNote] = nil
    end
  end
  midiTriggerMappings[midiNote] = {scaleNoteIndex = scaleNoteIndex, chordTypeIndex = chordTypeIndex}
  saveMidiTriggerMappings()
  updateScaleFilterState()
end

function clearMidiTriggerMapping(scaleNoteIndex, chordTypeIndex)
  for note, data in pairs(midiTriggerMappings) do
    if data.scaleNoteIndex == scaleNoteIndex and data.chordTypeIndex == chordTypeIndex then
      midiTriggerMappings[note] = nil
    end
  end
  saveMidiTriggerMappings()
  updateScaleFilterState()
end

function getMidiTriggerNoteForChord(scaleNoteIndex, chordTypeIndex)
  for note, data in pairs(midiTriggerMappings) do
    if data.scaleNoteIndex == scaleNoteIndex and data.chordTypeIndex == chordTypeIndex then
      return note
    end
  end
  return nil
end

function setMidiTriggerColumnMapping(midiNote, columnIndex)
  for existingNote, col in pairs(midiTriggerColumnMappings) do
    if col == columnIndex then
      midiTriggerColumnMappings[existingNote] = nil
    end
  end
  midiTriggerColumnMappings[midiNote] = columnIndex
  saveMidiTriggerMappings()
  updateScaleFilterState()
end

function clearMidiTriggerColumnMapping(columnIndex)
  for note, col in pairs(midiTriggerColumnMappings) do
    if col == columnIndex then
      midiTriggerColumnMappings[note] = nil
    end
  end
  saveMidiTriggerMappings()
  updateScaleFilterState()
end

function getMidiTriggerNoteForColumn(columnIndex)
  for note, col in pairs(midiTriggerColumnMappings) do
    if col == columnIndex then
      return note
    end
  end
  return nil
end

function getMidiNoteName(midiNote)
  local noteNames = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
  local octave = math.floor(midiNote / 12) - 1
  local noteName = noteNames[(midiNote % 12) + 1]
  return noteName .. octave
end

function getChordMapsFolder()
  local scriptPath = reaper.GetResourcePath() .. "/Scripts/TK Scripts/Midi/TK_ChordGun/ChordMaps"
  reaper.RecursiveCreateDirectory(scriptPath, 0)
  return scriptPath
end

function saveChordMapPreset(name)
  local folder = getChordMapsFolder()
  local filepath = folder .. "/" .. name .. ".txt"
  local file = io.open(filepath, "w")
  if file then
    file:write("[MODE]\n")
    file:write(tostring(midiTriggerMode) .. "\n")
    file:write("[CHORDS]\n")
    for note, data in pairs(midiTriggerMappings) do
      file:write(string.format("%d,%d,%d\n", note, data.scaleNoteIndex, data.chordTypeIndex))
    end
    file:write("[COLUMNS]\n")
    for note, col in pairs(midiTriggerColumnMappings) do
      file:write(string.format("%d,%d\n", note, col))
    end
    file:close()
    return true
  end
  return false
end

function loadChordMapPreset(name)
  local folder = getChordMapsFolder()
  local filepath = folder .. "/" .. name .. ".txt"
  local file = io.open(filepath, "r")
  if file then
    midiTriggerMappings = {}
    midiTriggerColumnMappings = {}
    local section = ""
    local hasChordMappings = false
    local hasColumnMappings = false
    local explicitMode = nil
    
    for line in file:lines() do
      if line == "[MODE]" then
        section = "mode"
      elseif line == "[CHORDS]" then
        section = "chords"
      elseif line == "[COLUMNS]" then
        section = "columns"
      elseif section == "mode" then
        explicitMode = tonumber(line)
      elseif section == "chords" then
        local note, s, c = line:match("(%d+),(%d+),(%d+)")
        if note and s and c then
          midiTriggerMappings[tonumber(note)] = {scaleNoteIndex = tonumber(s), chordTypeIndex = tonumber(c)}
          hasChordMappings = true
        end
      elseif section == "columns" then
        local note, col = line:match("(%d+),(%d+)")
        if note and col then
          midiTriggerColumnMappings[tonumber(note)] = tonumber(col)
          hasColumnMappings = true
        end
      else
        local note, s, c = line:match("(%d+),(%d+),(%d+)")
        if note and s and c then
          midiTriggerMappings[tonumber(note)] = {scaleNoteIndex = tonumber(s), chordTypeIndex = tonumber(c)}
          hasChordMappings = true
        end
      end
    end
    file:close()
    
    if explicitMode then
      midiTriggerMode = explicitMode
    elseif hasColumnMappings and not hasChordMappings then
      midiTriggerMode = 2
    elseif hasChordMappings and not hasColumnMappings then
      midiTriggerMode = 1
    end
    
    saveMidiTriggerMappings()
    updateScaleFilterState()
    currentTriggerPreset = name
    return true
  end
  return false
end

function deleteChordMapPreset(name)
  local folder = getChordMapsFolder()
  local filepath = folder .. "/" .. name .. ".txt"
  os.remove(filepath)
end

function loadBuiltInPreset_WhiteKeys7()
  midiTriggerColumnMappings = {}
  midiTriggerMappings = {}
  midiTriggerColumnMappings[36] = 1  -- C2 -> kolom 1
  midiTriggerColumnMappings[38] = 2  -- D2 -> kolom 2
  midiTriggerColumnMappings[40] = 3  -- E2 -> kolom 3
  midiTriggerColumnMappings[41] = 4  -- F2 -> kolom 4
  midiTriggerColumnMappings[43] = 5  -- G2 -> kolom 5
  midiTriggerColumnMappings[45] = 6  -- A2 -> kolom 6
  midiTriggerColumnMappings[47] = 7  -- B2 -> kolom 7
  midiTriggerMode = 2
  midiTriggerEnabled = true
  saveMidiTriggerMappings()
  updateScaleFilterState()
  currentTriggerPreset = "White Keys (C2-B2)"
end

function getChordMapPresets()
  local folder = getChordMapsFolder()
  local presets = {}
  local i = 0
  repeat
    local file = reaper.EnumerateFiles(folder, i)
    if file and file:match("%.txt$") then
      local presetName = (file:gsub("%.txt$", ""))
      table.insert(presets, presetName)
    end
    i = i + 1
  until not file
  table.sort(presets)
  return presets
end

function setScaleFilterMode(mode)
  scaleFilterMode = mode
  setValue("scaleFilterMode", tostring(mode))
  updateScaleFilterState()
end

function cycleScaleFilterMode()
  local nextMode = (scaleFilterMode + 1) % 3
  
  -- Check for JSFX if enabling Filter or Remap
  if nextMode > 0 then
    local track = reaper.GetSelectedTrack(0, 0)
    local jsfxFound = false
    
    if track then
      local inputFxCount = reaper.TrackFX_GetRecCount(track)
      for i = 0, inputFxCount - 1 do
        local retval, fxName = reaper.TrackFX_GetFXName(track, i + 0x1000000, "")
        if fxName and fxName:match("TK Scale Filter") then 
          jsfxFound = true 
          break 
        end
      end
    end
    
    if not jsfxFound then
      local result = reaper.ShowMessageBox("TK Scale Filter JSFX is required for Filter/Remap modes.\n\nIt was not found on the selected track's Input FX.\n\nAdd it now?", "Setup Required", 4)
      if result == 6 then -- Yes
        if not track then
           reaper.ShowMessageBox("Please select a track first!", "No Track Selected", 0)
           return
        end
        local fxIndex = reaper.TrackFX_AddByName(track, "JS: TK_Scale_Filter", true, -1000 - 0x1000000)
        if fxIndex < 0 then
           reaper.ShowMessageBox("Could not add TK Scale Filter.", "Setup Failed", 0)
           return
        end
        -- Added successfully, proceed
      else
        -- User said No, cancel mode change
        return
      end
    end
  end

  scaleFilterMode = nextMode
  setScaleFilterMode(scaleFilterMode)
end

function getScaleFilterModeText()
  if scaleFilterMode == 0 then return "Off"
  elseif scaleFilterMode == 1 then return "Filter"
  else return "Remap"
  end
end


local recognizedChord = ""
local chordInputNotes = {}
local lastInputIdx = nil

function updateChordInputTracking()

  if not reaper.MIDI_GetRecentInputEvent then return end
  
  local currentIdx = reaper.MIDI_GetRecentInputEvent(0)
  if not currentIdx then return end
  

  if lastInputIdx == nil then
    lastInputIdx = currentIdx
    chordInputNotes = {}
    return
  end
  
  if currentIdx == lastInputIdx then return end
  


  local eventsToProcess = {}
  local i = 0
  local maxIterations = 100
  
  repeat
    local eventIdx, eventBuf = reaper.MIDI_GetRecentInputEvent(i)
    if not eventIdx then break end
    if eventIdx <= lastInputIdx then break end
    
    table.insert(eventsToProcess, {idx = eventIdx, buf = eventBuf})
    
    i = i + 1
  until i >= maxIterations
  

  table.sort(eventsToProcess, function(a, b) return a.idx < b.idx end)
  

  for _, event in ipairs(eventsToProcess) do
    local eventBuf = event.buf
    if eventBuf and #eventBuf >= 3 then
      local msg1 = string.byte(eventBuf, 1)
      local msg2 = string.byte(eventBuf, 2)
      local msg3 = string.byte(eventBuf, 3)
      
      local status = msg1 & 0xF0
      local isNoteOn = (status == 0x90 and msg3 > 0)
      local isNoteOff = (status == 0x80) or (status == 0x90 and msg3 == 0)
      
      if isNoteOn then
        chordInputNotes[msg2] = true
      elseif isNoteOff then
        chordInputNotes[msg2] = nil
      end
    end
  end
  
  lastInputIdx = currentIdx
end

local function getActiveExternalNotes()

  local notes = {}
  for note, _ in pairs(chordInputNotes) do

    if midiTriggerEnabled then
      if midiTriggerMode == 1 and midiTriggerMappings[note] then
        goto continue
      elseif midiTriggerMode == 2 and midiTriggerColumnMappings[note] then
        goto continue
      end
    end

    local noteToAnalyze = note
    if scaleFilterMode == 2 and scalePattern then
      local noteInOctave = note % 12

      local whiteKeys = {0, 2, 4, 5, 7, 9, 11}
      local isWhiteKey = false
      local whiteKeyIndex = 0
      for i, wk in ipairs(whiteKeys) do
        if noteInOctave == wk then
          isWhiteKey = true
          whiteKeyIndex = i
          break
        end
      end
      

      if isWhiteKey then

        local scaleNotes = {}
        for i = 1, 12 do
          if scalePattern[i] then

            table.insert(scaleNotes, i - 1)
          end
        end
        

        if scaleNotes[whiteKeyIndex] then
          local octave = math.floor(note / 12)
          noteToAnalyze = scaleNotes[whiteKeyIndex] + (octave * 12)
        end
      end
    end
    table.insert(notes, noteToAnalyze)
    ::continue::
  end
  table.sort(notes)
  return notes
end

function analyzeChord(midiNotes)
  if #midiNotes < 2 then return nil end
  

  local noteClasses = {}
  local noteClassSet = {}
  for _, note in ipairs(midiNotes) do
    local noteClass = note % 12
    if not noteClassSet[noteClass] then
      table.insert(noteClasses, noteClass)
      noteClassSet[noteClass] = true
    end
  end
  table.sort(noteClasses)
  
  if #noteClasses < 2 then return nil end
  

  local chordPatterns = {
    {name = "5", pattern = {0, 7}},
    {name = "maj", pattern = {0, 4, 7}},
    {name = "min", pattern = {0, 3, 7}},
    {name = "dim", pattern = {0, 3, 6}},
    {name = "aug", pattern = {0, 4, 8}},
    {name = "sus2", pattern = {0, 2, 7}},
    {name = "sus4", pattern = {0, 5, 7}},
    {name = "maj7", pattern = {0, 4, 7, 11}},
    {name = "min7", pattern = {0, 3, 7, 10}},
    {name = "7", pattern = {0, 4, 7, 10}},
    {name = "dim7", pattern = {0, 3, 6, 9}},
    {name = "min7b5", pattern = {0, 3, 6, 10}},
    {name = "maj9", pattern = {0, 2, 4, 7, 11}},
    {name = "min9", pattern = {0, 2, 3, 7, 10}},
  }
  

  local bestMatch = nil
  local bestScore = 0
  
  for _, rootNote in ipairs(noteClasses) do

    local intervals = {}
    for _, note in ipairs(noteClasses) do
      table.insert(intervals, (note - rootNote + 12) % 12)
    end
    table.sort(intervals)
    

    for _, chordDef in ipairs(chordPatterns) do
      local pattern = chordDef.pattern
      if #intervals >= #pattern then
        local matches = 0
        for _, interval in ipairs(pattern) do
          for _, noteInterval in ipairs(intervals) do
            if interval == noteInterval then
              matches = matches + 1
              break
            end
          end
        end
        
        local score = matches

        if scalePattern and scalePattern[(rootNote % 12) + 1] then
          score = score + 0.5
        end

        if rootNote == (midiNotes[1] % 12) then
          score = score + 1
        end
        
        if matches == #pattern and score > bestScore then
          bestScore = score
          bestMatch = {root = rootNote, chord = chordDef.name, bass = midiNotes[1] % 12}
        end
      end
    end
  end
  
  return bestMatch
end

function getChordName(chordAnalysis)
  if not chordAnalysis then return "" end
  

  local function getNoteName(noteClass)
    local sharpNames = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
    local flatNames = {"C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"}
    

    if scalePattern then

      local hasFlats = scalePattern[2] or scalePattern[4] or scalePattern[9] or scalePattern[11]
      if hasFlats then
        return flatNames[noteClass + 1]
      end
    end
    

    return notes and notes[noteClass + 1] or sharpNames[noteClass + 1]
  end
  
  local rootName = getNoteName(chordAnalysis.root)
  local chordType = chordAnalysis.chord
  

  local chordName = rootName
  if chordType == "maj" then

  elseif chordType == "min" then
    chordName = chordName .. "m"
  else
    chordName = chordName .. chordType
  end
  

  if chordAnalysis.bass ~= chordAnalysis.root then
    local bassName = getNoteName(chordAnalysis.bass)
    chordName = chordName .. "/" .. bassName
  end
  
  return chordName
end

function updateChordRecognition()
  updateChordInputTracking()
  
  local activeNotes = getActiveExternalNotes()
  

  if #activeNotes == 0 then
    recognizedChord = ""
    return
  end
  
  if #activeNotes >= 2 then
    local chordAnalysis = analyzeChord(activeNotes)
    if chordAnalysis then
      local chordName = getChordName(chordAnalysis)
      if chordName and chordName ~= "" then
        recognizedChord = chordName
      else

        local noteNames = {}
        for _, note in ipairs(activeNotes) do
          table.insert(noteNames, notes[(note % 12) + 1])
        end
        recognizedChord = table.concat(noteNames, " ")
      end
    else

      local noteNames = {}
      for _, note in ipairs(activeNotes) do
        table.insert(noteNames, notes[(note % 12) + 1])
      end
      recognizedChord = table.concat(noteNames, " ")
    end
  elseif #activeNotes >= 1 then

    local noteNames = {}
    for _, note in ipairs(activeNotes) do
      table.insert(noteNames, notes[(note % 12) + 1])
    end
    recognizedChord = table.concat(noteNames, " ")
  end
end

local function setTableValue(key, value)
  reaper.SetProjExtState(Context.activeProjectIndex, Context.sectionName, key, table.concat(value, ","))
end

local function getTableValue(key, defaultValue)

  local valueExists, value = reaper.GetProjExtState(Context.activeProjectIndex, Context.sectionName, key)

  if valueExists == 0 then
    setTableValue(key, defaultValue)
    return defaultValue
  end

  return getTableFromString(value)
end

--[[ ]]--

function getScaleTonicNote()
  return tonumber(getValue(ConfigKeys.scaleTonicNote, defaultScaleTonicNoteValue))
end

function setScaleTonicNote(arg)
  setValue(ConfigKeys.scaleTonicNote, arg)
end

--

function getScaleType()
  return tonumber(getValue(ConfigKeys.scaleType, defaultScaleTypeValue))
end

function setScaleType(arg)
  setValue(ConfigKeys.scaleType, arg)
end

--


function getScaleSystemIndex()
  local index = tonumber(reaper.GetExtState("TK_ChordGun", "scaleSystem"))
  if not index or index < 1 or index > #scaleSystems then
    return 1
  end
  return index
end

function setScaleSystemIndex(index)
  reaper.SetExtState("TK_ChordGun", "scaleSystem", tostring(index), true)
end

function getScaleWithinSystemIndex()
  local systemIndex = getScaleSystemIndex()
  local index = tonumber(reaper.GetExtState("TK_ChordGun", "scaleWithinSystem"))
  

  local system = scaleSystems[systemIndex]
  if not index or index < 1 or not system or index > #system.scales then
    return 1
  end
  return index
end

function setScaleWithinSystemIndex(index)
  reaper.SetExtState("TK_ChordGun", "scaleWithinSystem", tostring(index), true)
end


function getScaleIndexFromSystemIndices(systemIndex, scaleIndex)
  local flatIndex = 0
  for i = 1, systemIndex - 1 do
    flatIndex = flatIndex + #scaleSystems[i].scales
  end
  return flatIndex + scaleIndex
end


function getSystemIndicesFromScaleIndex(scaleIndex)
  local currentIndex = 0
  for systemIdx, system in ipairs(scaleSystems) do
    for scaleIdx, scale in ipairs(system.scales) do
      currentIndex = currentIndex + 1
      if currentIndex == scaleIndex then
        return systemIdx, scaleIdx
      end
    end
  end
  return 1, 1
end

--

function getScaleNotesText()
  return getValue(ConfigKeys.scaleNotesText, defaultScaleNotesTextValue)
end

function setScaleNotesText(arg)
  setValue(ConfigKeys.scaleNotesText, arg)
end

--

function getChordText()
  return getValue(ConfigKeys.chordText, defaultChordTextValue)
end

function setChordText(arg)
  setValue(ConfigKeys.chordText, arg)
end

--

function getChordInversionMin()
  return -8
end

--

function getChordInversionMax()
  return 8
end

--

function getSelectedScaleNote()
  return tonumber(getValue(ConfigKeys.selectedScaleNote, defaultSelectedScaleNote))
end

function setSelectedScaleNote(arg)
  setValue(ConfigKeys.selectedScaleNote, arg)
end

--

function getOctave()
  return tonumber(getValue(ConfigKeys.octave, defaultOctave))
end

function setOctave(arg)
  setValue(ConfigKeys.octave, arg)
end

--

function getOctaveMin()
  return -1
end

--

function getOctaveMax()
  return 8
end

--

function getSelectedChordTypes()

  return getTableValue(ConfigKeys.selectedChordTypes, defaultSelectedChordTypes)
end

function getSelectedChordType(index)

  local temp = getTableValue(ConfigKeys.selectedChordTypes, defaultSelectedChordTypes)
  return tonumber(temp[index])
end

function setSelectedChordType(index, arg)

  local temp = getSelectedChordTypes()
  temp[index] = arg
  setTableValue(ConfigKeys.selectedChordTypes, temp)
end

--

function getScaleNoteNames()
  return getTableValue(ConfigKeys.scaleNoteNames, defaultScaleNoteNames)
end

function getScaleNoteName(index)
  local temp = getTableValue(ConfigKeys.scaleNoteNames, defaultScaleNoteNames)
  return temp[index]
end

function setScaleNoteName(index, arg)

  local temp = getScaleNoteNames()
  temp[index] = arg
  setTableValue(ConfigKeys.scaleNoteNames, temp)
end

--

function getScaleDegreeHeaders()
  return getTableValue(ConfigKeys.scaleDegreeHeaders, defaultScaleDegreeHeaders)
end

function getScaleDegreeHeader(index)
  local temp = getTableValue(ConfigKeys.scaleDegreeHeaders, defaultScaleDegreeHeaders)
  return temp[index]
end

function setScaleDegreeHeader(index, arg)

  local temp = getScaleDegreeHeaders()
  temp[index] = arg
  setTableValue(ConfigKeys.scaleDegreeHeaders, temp)
end

--

function getChordInversionStates()
  return getTableValue(ConfigKeys.chordInversionStates, defaultInversionStates)
end

function getChordInversionState(index)

  local temp = getTableValue(ConfigKeys.chordInversionStates, defaultInversionStates)
  local value = temp[index]
  if value == nil then
    return 0
  end
  return tonumber(value)
end

function setChordInversionState(index, arg)

  local temp = getChordInversionStates()
  temp[index] = arg
  setTableValue(ConfigKeys.chordInversionStates, temp)
end

--

function resetSelectedChordTypes()

  local numberOfSelectedChordTypes = 12

  for i = 1, numberOfSelectedChordTypes do
    setSelectedChordType(i, 1)
  end
end

function resetChordInversionStates()

  local numberOfChordInversionStates = 12

  for i = 1, numberOfChordInversionStates do
    setChordInversionState(i, 0)
  end
end

--

function getNotesThatArePlaying()
  local values = getTableValue(ConfigKeys.notesThatArePlaying, defaultNotesThatArePlaying)
  local notes = {}
  for _, v in ipairs(values) do
    local n = tonumber(v)
    if n then table.insert(notes, n) end
  end
  return notes
end

function setNotesThatArePlaying(arg)
  setTableValue(ConfigKeys.notesThatArePlaying, arg)
end

--

function getDockState()
  return getPersistentNumber(ConfigKeys.dockState, defaultDockState)
end

function setDockState(arg)
  setPersistentNumber(ConfigKeys.dockState, arg)
end

function windowShouldBeDocked()
  return getPersistentValue(ConfigKeys.windowShouldBeDocked) == tostring(true)
end

function setWindowShouldBeDocked(arg)
  setPersistentValue(ConfigKeys.windowShouldBeDocked, tostring(arg))
end

function getInterfaceXPosition()
  return getPersistentNumber(ConfigKeys.interfaceXPosition, defaultInterfaceXPosition())
end

function setInterfaceXPosition(arg)
  setPersistentNumber(ConfigKeys.interfaceXPosition, arg)
end

function getInterfaceYPosition()
  return getPersistentNumber(ConfigKeys.interfaceYPosition, defaultInterfaceYPosition())
end

function setInterfaceYPosition(arg)
  setPersistentNumber(ConfigKeys.interfaceYPosition, arg)
end

function getInterfaceWidth()
  return getPersistentNumber(ConfigKeys.interfaceWidth, baseWidth * defaultUiScale)
end

function setInterfaceWidth(arg)
  setPersistentNumber(ConfigKeys.interfaceWidth, arg)
end

function getInterfaceHeight()
  return getPersistentNumber(ConfigKeys.interfaceHeight, baseHeight * defaultUiScale)
end

function setInterfaceHeight(arg)
  setPersistentNumber(ConfigKeys.interfaceHeight, arg)
end


local noteLengthOptions = {
  {label = "Time Selection", qn = -1},
  {label = "Grid", qn = nil},
  {label = "1/32", qn = 0.125},
  {label = "1/16", qn = 0.25},
  {label = "1/8",  qn = 0.5},
  {label = "1/4",  qn = 1.0},
  {label = "1/2",  qn = 2.0},
  {label = "1 bar", qn = 4.0},
  {label = "2 bars", qn = 8.0},
  {label = "4 bars", qn = 16.0},
  {label = "8 bars", qn = 32.0}
}
local noteLengthLabels = {}
for i, option in ipairs(noteLengthOptions) do
  noteLengthLabels[i] = option.label
end
local defaultNoteLengthIndex = 1

function getNoteLengthIndex()
  local index = getPersistentNumber(ConfigKeys.noteLengthIndex, defaultNoteLengthIndex) or defaultNoteLengthIndex
  if index < 1 then index = 1 end
  if index > #noteLengthOptions then index = #noteLengthOptions end
  return math.floor(index)
end

function setNoteLengthIndex(index)
  setPersistentNumber(ConfigKeys.noteLengthIndex, index)
end

Timer = {}
Timer.__index = Timer

function Timer:new(numberOfSeconds)

  local self = {}
  setmetatable(self, Timer)

  self.startingTime = reaper.time_precise()
  self.numberOfSeconds = numberOfSeconds
  self.timerIsStopped = true

  return self
end

function Timer:start()

	self.timerIsStopped = false
	self.startingTime = reaper.time_precise()
end

function Timer:stop()

	self.timerIsStopped = true
end

function Timer:timeHasElapsed()

	local currentTime = reaper.time_precise()

	if self.timerIsStopped then
		return false
	end

	if currentTime - self.startingTime > self.numberOfSeconds then
		return true
	else
		return false
	end
end

function Timer:timeHasNotElapsed()
	return not self:timeHasElapsed()
end
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/TK Scripts/Midi/TK_ChordGun"

mouseButtonIsNotPressedDown = true

currentWidth = 0

scaleTonicNote = getScaleTonicNote()
scaleType = getScaleType()

guiShouldBeUpdated = false


scaleSystems = Data.scaleSystems
scales = Data.scales

local workingDirectory = reaper.GetResourcePath() .. "/Scripts/TK Scripts/Midi/TK_ChordGun"

notes = Data.notes
flatNotes = Data.flatNotes

function getScalePattern(scaleTonicNote, scale)

  local scalePatternString = scale['pattern']
  local scalePattern = {false,false,false,false,false,false,false,false,false,false,false}

  for i = 0, #scalePatternString - 1 do
    local note = getNotesIndex(scaleTonicNote+i)
    if scalePatternString:sub(i+1, i+1) == '1' then
      scalePattern[note] = true
    end
  end
  return scalePattern
end

function getNotesIndex(note) 
   return ((note - 1) % 12) + 1
end

function getNoteName(note)

  local noteName = getSharpNoteName(note)
  
  if not string.match(getScaleNotesText(), noteName) then
    return getFlatNoteName(note)
  else
    return noteName
  end
end

function getSharpNoteName(note)
  local notesIndex = getNotesIndex(note)
  return notes[notesIndex]
end

function getFlatNoteName(note)
  local notesIndex = getNotesIndex(note)
  return flatNotes[notesIndex]
end

function chordIsNotAlreadyIncluded(scaleChordsForRootNote, chordCode)

  for chordIndex, chord in ipairs(scaleChordsForRootNote) do
  
    if chord.code == chordCode then
      return false
    end
  end
  
  return true
end

function getNumberOfScaleChordsForScaleNoteIndex(scaleNoteIndex)

  local chordCount = 0
  local scaleChordsForRootNote = {}
  
  for chordIndex, chord in ipairs(chords) do
  
    if chordIsInScale(scaleNotes[scaleNoteIndex], chordIndex) then
      chordCount = chordCount + 1
      scaleChordsForRootNote[chordCount] = chord   
    end
  end

  return chordCount
end

function getScaleChordsForRootNote(rootNote)
  
  local chordCount = 0
  local scaleChordsForRootNote = {}
  local limit = getChordVisibilityLimit()
  
  for chordIndex, chord in ipairs(chords) do
  
    -- Filter by visibility mode
    if chordIndex <= limit or (chordVisibilityMode == 3) then
        if chordIsInScale(rootNote, chordIndex) then
          chordCount = chordCount + 1
          scaleChordsForRootNote[chordCount] = chord   
        end
    end
  end
    
  --[[  
  if preferences.enableModalMixtureCheckbox.value then

    for chordIndex, chord in ipairs(chords) do
             
      if chordIsNotAlreadyIncluded(scaleChordsForRootNote, chord.code) and chordIsInModalMixtureScale(rootNote, chordIndex) then
        chordCount = chordCount + 1
        scaleChordsForRootNote[chordCount] = chord
      end
    end
  end
  ]]--



  for chordIndex, chord in ipairs(chords) do
           
    -- Filter by visibility mode
    if chordIndex <= limit or (chordVisibilityMode == 3) then
        if chordIsNotAlreadyIncluded(scaleChordsForRootNote, chord.code) then
          chordCount = chordCount + 1
          scaleChordsForRootNote[chordCount] = chord
        end
    end
  end
  
  return scaleChordsForRootNote
end

function noteIsInScale(note)
  return scalePattern[getNotesIndex(note)]
end

function noteIsNotInScale(note)
  return not noteIsInScale(note)
end

function chordIsInScale(rootNote, chordIndex)

  local chord = chords[chordIndex]
  local chordPattern = chord['pattern']
  
  for i = 0, #chordPattern do
    local note = getNotesIndex(rootNote+i)
    if chordPattern:sub(i+1, i+1) == '1' and noteIsNotInScale(note) then
      return false
    end
  end
  
  return true
end

function noteIsInModalMixtureScale(note)

  local modalMixtureScaleType = 2
  local modalMixtureScalePattern = getScalePattern(getScaleTonicNote(), scales[modalMixtureScaleType])
  return modalMixtureScalePattern[getNotesIndex(note)]
end

function noteIsNotInModalMixtureScale(note)
  return not noteIsInModalMixtureScale(note)
end

function getChordIntervals(chord)

  local pattern = chord.pattern
  local stepIntervals = {}
  local cumulativeIntervals = {}
  local lastPosition = nil
  

  for i = 0, #pattern - 1 do
    if pattern:sub(i + 1, i + 1) == "1" then

      table.insert(cumulativeIntervals, i)
      

      if lastPosition ~= nil then
        table.insert(stepIntervals, i - lastPosition)
      end
      lastPosition = i
    end
  end
  

  if #stepIntervals > 0 then
    return table.concat(stepIntervals, "-"), table.concat(cumulativeIntervals, "-")
  end
  return nil, nil
end

function chordIsInModalMixtureScale(rootNote, chordIndex)

  local chord = chords[chordIndex]
  local chordPattern = chord['pattern']
  
  for i = 0, #chordPattern do
    local note = getNotesIndex(rootNote+i)
        
    if chordPattern:sub(i+1, i+1) == '1' and noteIsNotInModalMixtureScale(note) then
      return false
    end
  end
  
  return true
end
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/TK Scripts/Midi/TK_ChordGun"

function updateScaleDegreeHeaders()


  local currentScale = scales[getScaleType()]
  local isCustomScale = currentScale.isCustom == true
  

  if isCustomScale then
    for i = 1, #scaleNotes do
      setScaleDegreeHeader(i, tostring(i))
    end
    return
  end
  

  local minorSymbols = {'i', 'ii', 'iii', 'iv', 'v', 'vi', 'vii'}
  local majorSymbols = {'I', 'II', 'III', 'IV', 'V', 'VI', 'VII'}
  local diminishedSymbol = 'o'
  local augmentedSymbol = '+'
  local sixthSymbol = '6'
  local seventhSymbol = '7'
  

  local semitoneToScaleDegree = {
    [0] = 1,
    [1] = 2,
    [2] = 2,
    [3] = 3,
    [4] = 3,
    [5] = 4,
    [6] = 5,
    [7] = 5,
    [8] = 6,
    [9] = 6,
    [10] = 7,
    [11] = 7
  }
  
  local tonicNote = getScaleTonicNote()
  
  for i = 1, #scaleNotes do
  
    local symbol = ""
    local chord = scaleChords[i][1]
    

    local noteOffset = (scaleNotes[i] - tonicNote) % 12
    local scaleDegree = semitoneToScaleDegree[noteOffset]
    
    if string.match(chord.code, "major") or chord.code == '7' then
      symbol = majorSymbols[scaleDegree]
    else
      symbol = minorSymbols[scaleDegree]
    end
    
    if (chord.code == 'aug') then
      symbol = symbol .. augmentedSymbol
    end

    if (chord.code == 'dim') then
      symbol = symbol .. diminishedSymbol
    end

    if string.match(chord.code, "6") then
      symbol = symbol .. sixthSymbol
    end
    
    if string.match(chord.code, "7") then
      symbol = symbol .. seventhSymbol
    end
        
    setScaleDegreeHeader(i, symbol) 
  end
end

--[[

  setDrawColorToRed()
  gfx.setfont(1, "Arial")       <
  local degreeSymbolCharacter = 0x00B0  <
  gfx.drawchar(degreeSymbolCharacter)

]]--

local tolerance = 0.000001

function activeMidiEditor()
  return reaper.MIDIEditor_GetActive()
end

function activeTake()

  local editor = reaper.MIDIEditor_GetActive()
  if editor then
    return reaper.MIDIEditor_GetTake(editor)
  end

  -- Check memory first (if valid and selected)
  if lastActiveTake and reaper.ValidatePtr(lastActiveTake, "MediaItem_Take*") then
      local item = reaper.GetMediaItemTake_Item(lastActiveTake)
      if reaper.IsMediaItemSelected(item) then
          return lastActiveTake
      end
  end

  local item = reaper.GetSelectedMediaItem(0, 0)
  if item then
    local take = reaper.GetActiveTake(item)
    if take and reaper.TakeIsMIDI(take) then
      return take
    end
  end

  return nil
end

function activeMediaItem()
  local take = activeTake()
  if take then
    return reaper.GetMediaItemTake_Item(take)
  end
  return nil
end

function activeTrack()
  local take = activeTake()
  if take then
    return reaper.GetMediaItemTake_Track(take)
  end
  return nil
end

function mediaItemStartPosition()
  local item = activeMediaItem()
  if item then
    return reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  end
  return 0
end

function mediaItemStartPositionPPQ()
  local take = activeTake()
  if take then
    return reaper.MIDI_GetPPQPosFromProjTime(take, mediaItemStartPosition())
  end
  return 0
end

function mediaItemStartPositionQN()
  local take = activeTake()
  if take then
    return reaper.MIDI_GetProjQNFromPPQPos(take, mediaItemStartPositionPPQ())
  end
  return 0
end

local function mediaItemLength()
  local item = activeMediaItem()
  if item then
    return reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  end
  return 0
end

local function mediaItemEndPosition()
  return mediaItemStartPosition() + mediaItemLength()
end

local function cursorPosition()
  return reaper.GetCursorPosition()
end

local function loopStartPosition()

  local loopStartPosition, _ = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
  return loopStartPosition
end

local function loopEndPosition()

  local _, loopEndPosition = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
  return loopEndPosition
end

local function noteLengthOld()

  local noteLengthQN = getNoteLengthQN()
  local noteLengthPPQ = reaper.MIDI_GetPPQPosFromProjQN(activeTake(), noteLengthQN)
  return reaper.MIDI_GetProjTimeFromPPQPos(activeTake(), noteLengthPPQ)
end

local function noteLength()
  local index = getNoteLengthIndex()
  local option = noteLengthOptions[index]

  if option and option.qn == -1 then
      local startLoop, endLoop = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
      if startLoop ~= endLoop then
        return endLoop - startLoop
      end
      return gridUnitLength()
  end

  if option and option.qn then
      local take = activeTake()
      if take then
          local startPos = reaper.GetCursorPosition()
          local startPPQ = reaper.MIDI_GetPPQPosFromProjTime(take, startPos)
          local startQN_ = reaper.MIDI_GetProjQNFromPPQPos(take, startPPQ)
          local endQN_ = startQN_ + option.qn
          local endPPQ = reaper.MIDI_GetPPQPosFromProjQN(take, endQN_)
          local endTime = reaper.MIDI_GetProjTimeFromPPQPos(take, endPPQ)
          
          return endTime - startPos
      else
          local bpm = reaper.Master_GetTempo()
          return (60/bpm) * option.qn
      end
  end

  return gridUnitLength()
end


function notCurrentlyRecording()
  
  local activeProjectIndex = 0
  return reaper.GetPlayStateEx(activeProjectIndex) & 4 ~= 4
end

function setEditCursorPosition(arg)

  local activeProjectIndex = 0
  local moveView = false
  local seekPlay = false
  reaper.SetEditCurPos2(activeProjectIndex, arg, moveView, seekPlay)
end

local function moveEditCursorPosition(arg)

  local moveTimeSelection = false
  reaper.MoveEditCursor(arg, moveTimeSelection)
end

local function repeatIsNotOn()
  return reaper.GetSetRepeat(-1) == 0
end

local function loopIsActive()

  if repeatIsNotOn() then
    return false
  end

  if loopStartPosition() < mediaItemStartPosition() and loopEndPosition() < mediaItemStartPosition() then
    return false
  end

  if loopStartPosition() > mediaItemEndPosition() and loopEndPosition() > mediaItemEndPosition() then
    return false
  end

  if loopStartPosition() == loopEndPosition() then
    return false
  else
    return true
  end
end

function moveCursor(keepNotesSelected, selectedChord)

  if keepNotesSelected then

    local noteEndPositionInProjTime = reaper.MIDI_GetProjTimeFromPPQPos(activeTake(), selectedChord.longestEndPosition)
    local noteLengthOfSelectedNote = noteEndPositionInProjTime-cursorPosition()

    if loopIsActive() and loopEndPosition() < mediaItemEndPosition() then

      if cursorPosition() + noteLengthOfSelectedNote >= loopEndPosition() - tolerance then

        if loopStartPosition() > mediaItemStartPosition() then
          setEditCursorPosition(loopStartPosition())
        else
          setEditCursorPosition(mediaItemStartPosition())
        end

      else
        
        moveEditCursorPosition(noteLengthOfSelectedNote)  
      end

    elseif loopIsActive() and mediaItemEndPosition() <= loopEndPosition() then 

      if cursorPosition() + noteLengthOfSelectedNote >= mediaItemEndPosition() - tolerance then

        if loopStartPosition() > mediaItemStartPosition() then
          setEditCursorPosition(loopStartPosition())
        else
          setEditCursorPosition(mediaItemStartPosition())
        end

      else
      
        moveEditCursorPosition(noteLengthOfSelectedNote)
      end

    elseif cursorPosition() + noteLengthOfSelectedNote >= mediaItemEndPosition() - tolerance then
      setEditCursorPosition(mediaItemStartPosition())
    else

      moveEditCursorPosition(noteLengthOfSelectedNote)
    end

  else

    if loopIsActive() and loopEndPosition() < mediaItemEndPosition() then

      if cursorPosition() + noteLength() >= loopEndPosition() - tolerance then

        if loopStartPosition() > mediaItemStartPosition() then
          setEditCursorPosition(loopStartPosition())
        else
          setEditCursorPosition(mediaItemStartPosition())
        end

      else
        moveEditCursorPosition(noteLength())
      end

    elseif loopIsActive() and mediaItemEndPosition() <= loopEndPosition() then 

      if cursorPosition() + noteLength() >= mediaItemEndPosition() - tolerance then

        if loopStartPosition() > mediaItemStartPosition() then
          setEditCursorPosition(loopStartPosition())
        else
          setEditCursorPosition(mediaItemStartPosition())
        end

      else
        moveEditCursorPosition(noteLength())
      end

    elseif cursorPosition() + noteLength() >= mediaItemEndPosition() - tolerance then
        setEditCursorPosition(mediaItemStartPosition())
    else

      moveEditCursorPosition(noteLength())
    end

  end

end

--

function getCursorPositionPPQ(take)
  take = take or activeTake()
  if take then
    return reaper.MIDI_GetPPQPosFromProjTime(take, cursorPosition())
  end
  return 0
end

local function getCursorPositionQN()
  local take = activeTake()
  if take then
    return reaper.MIDI_GetProjQNFromPPQPos(take, getCursorPositionPPQ(take))
  end
  return reaper.TimeMap2_timeToQN(0, cursorPosition())
end

function getNoteLengthQN()

  local option = noteLengthOptions[getNoteLengthIndex()] or noteLengthOptions[defaultNoteLengthIndex]
  local take = activeTake()


  if option and option.qn then
    return option.qn
  end


  if take then
    return reaper.MIDI_GetGrid(take)
  end


  return 0.25
end

function gridUnitLength()

  local take = activeTake()
  if not take then return 0 end

  local gridLengthQN = getNoteLengthQN()
  local mediaItemPlusGridLengthPPQ = reaper.MIDI_GetPPQPosFromProjQN(take, mediaItemStartPositionQN() + gridLengthQN)
  local mediaItemPlusGridLength = reaper.MIDI_GetProjTimeFromPPQPos(take, mediaItemPlusGridLengthPPQ)
  return mediaItemPlusGridLength - mediaItemStartPosition()
end

function getMidiEndPositionPPQ()
  local take = activeTake()
  if not take then return 0 end

  local startPosition = reaper.GetCursorPosition()
  local index = getNoteLengthIndex()
  local option = noteLengthOptions[index]
  
  local lengthTime
  
  if option and option.qn == -1 then
      local startLoop, endLoop = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
      if startLoop ~= endLoop then
          lengthTime = endLoop - startLoop
      else
          lengthTime = gridUnitLength()
      end
  elseif option and option.qn then
      local startPPQ = reaper.MIDI_GetPPQPosFromProjTime(take, startPosition)
      local startQN = reaper.MIDI_GetProjQNFromPPQPos(take, startPPQ)
      local endQN = startQN + option.qn
      local endPPQ = reaper.MIDI_GetPPQPosFromProjQN(take, endQN)
      local endTime = reaper.MIDI_GetProjTimeFromPPQPos(take, endPPQ)
      lengthTime = endTime - startPosition
  else
      lengthTime = gridUnitLength()
  end
  
  local endPositionPPQ = reaper.MIDI_GetPPQPosFromProjTime(take, startPosition + lengthTime)
  return endPositionPPQ
end

function deselectAllNotes()
  local take = activeTake()
  if not take then return end
  local selectAllNotes = false
  reaper.MIDI_SelectAll(take, selectAllNotes)
end

function getCurrentNoteChannel(channelArg)

  if channelArg ~= nil then
    return channelArg
  end

  if activeMidiEditor() == nil then
    return 0
  end

  return reaper.MIDIEditor_GetSetting_int(activeMidiEditor(), "default_note_chan")
end

function getCurrentVelocity()

  if activeMidiEditor() == nil then
    return 96
  end

  return reaper.MIDIEditor_GetSetting_int(activeMidiEditor(), "default_note_vel")
end

function getNumberOfNotes()
  local take = activeTake()
  if not take then return 0 end
  local _, numberOfNotes = reaper.MIDI_CountEvts(take)
  return numberOfNotes
end

function deleteNote(noteIndex)
  local take = activeTake()
  if not take then return end
  reaper.MIDI_DeleteNote(take, noteIndex)
end

function thereAreNotesSelected()

  local take = activeTake()
  if not take then return false end

  local numberOfNotes = getNumberOfNotes()

  for noteIndex = 0, numberOfNotes-1 do

    local _, noteIsSelected = reaper.MIDI_GetNote(take, noteIndex)

    if noteIsSelected then
      return true
    end
  end

  return false
end

function halveGridSize()

  if activeTake() == nil then
    return
  end

  local gridSize = reaper.MIDI_GetGrid(activeTake())/4

  if gridSize <= 1/1024 then
    return
  end

  local activeProjectIndex = 0
  reaper.SetMIDIEditorGrid(activeProjectIndex, gridSize/2)
end

function doubleGridSize()

  if activeTake() == nil then
    return
  end

  local gridSize = reaper.MIDI_GetGrid(activeTake())/4

  if gridSize >= 1024 then
    return
  end

  local activeProjectIndex = 0
  reaper.SetMIDIEditorGrid(activeProjectIndex, gridSize*2)
end

--

function deleteExistingNotesInNextInsertionTimePeriod(keepNotesSelected, selectedChord)

  local insertionStartTime = cursorPosition()

  local insertionEndTime = nil
  
  if keepNotesSelected then
    insertionEndTime = reaper.MIDI_GetProjTimeFromPPQPos(activeTake(), selectedChord.longestEndPosition)
  else
    insertionEndTime = insertionStartTime + noteLength()
  end

  local numberOfNotes = getNumberOfNotes()

  for noteIndex = numberOfNotes-1, 0, -1 do

    local _, _, _, noteStartPositionPPQ = reaper.MIDI_GetNote(activeTake(), noteIndex)
    local noteStartTime = reaper.MIDI_GetProjTimeFromPPQPos(activeTake(), noteStartPositionPPQ)

    if noteStartTime + tolerance >= insertionStartTime and noteStartTime + tolerance <= insertionEndTime then
      deleteNote(noteIndex)
    end
  end
end
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/TK Scripts/Midi/TK_ChordGun"

local function applyArpPattern(notes)
    if not arpEnabled then return notes end
    
    local newNotes = {}
    for i, v in ipairs(notes) do table.insert(newNotes, v) end
    
    if arpMode == 1 then -- Up
        table.sort(newNotes)
    elseif arpMode == 2 then -- Down
        table.sort(newNotes, function(a,b) return a > b end)
    elseif arpMode == 3 then -- Up/Down
        table.sort(newNotes)
        local count = #newNotes
        if count > 2 then
            local downNotes = {}
            for i = count - 1, 2, -1 do
                table.insert(downNotes, newNotes[i])
            end
            for _, v in ipairs(downNotes) do
                table.insert(newNotes, v)
            end
        end
    elseif arpMode == 4 then -- Random
        for i = #newNotes, 2, -1 do
            local j = math.random(i)
            newNotes[i], newNotes[j] = newNotes[j], newNotes[i]
        end
    elseif arpMode == 5 then -- Down/Up
        table.sort(newNotes, function(a,b) return a > b end)
        local count = #newNotes
        if count > 2 then
            local upNotes = {}
            for i = count - 1, 2, -1 do
                table.insert(upNotes, newNotes[i])
            end
            for _, v in ipairs(upNotes) do
                table.insert(newNotes, v)
            end
        end
    end
    
    return newNotes
end

function getBestVoiceLeadingInversion(root, chordData, octave)
    if not lastPlayedNotes or #lastPlayedNotes == 0 then return 0 end
    
    local lastAvg = getAveragePitch(lastPlayedNotes)
    local bestInversion = 0
    local minDiff = 10000
    
    -- Get base notes to determine number of possible inversions
    local baseNotes = getChordNotesArray(root, chordData, octave, 0)
    local numNotes = #baseNotes
    if numNotes == 0 then return 0 end
    
    local maxInversions = numNotes - 1
    
    for inv = 0, maxInversions do
        local candidateNotes = getChordNotesArray(root, chordData, octave, inv)
        local avg = getAveragePitch(candidateNotes)
        local diff = math.abs(avg - lastAvg)
        
        if diff < minDiff then
            minDiff = diff
            bestInversion = inv
        end
    end
    
    return bestInversion
end

function playMidiNote(midiNote, velocityOverride)

  local virtualKeyboardMode = 0
  local channel = getCurrentNoteChannel()
  
  if scaleFilterMode == 2 then
    channel = 15
  end

  local noteOnCommand = 0x90 + channel
  local velocity = velocityOverride or getCurrentVelocity()

  reaper.StuffMIDIMessage(virtualKeyboardMode, noteOnCommand, midiNote, velocity)
  registerInternalNoteEvent(midiNote, true)
end

function stopAllNotesFromPlaying()

  for midiNote = 0, 127 do

    local virtualKeyboardMode = 0
    local channel = getCurrentNoteChannel()
    
    if scaleFilterMode == 2 then
      channel = 15
    end

    local noteOffCommand = 0x80 + channel
    local velocity = 0

    reaper.StuffMIDIMessage(virtualKeyboardMode, noteOffCommand, midiNote, velocity)
  end

  if reaper.time_precise then
    suppressExternalMidiUntil = math.max(suppressExternalMidiUntil or 0, reaper.time_precise() + 0.05)
  end
end

function stopNoteFromPlaying(midiNote)

  local virtualKeyboardMode = 0
  local channel = getCurrentNoteChannel()
  
  if scaleFilterMode == 2 then
    channel = 15
  end

  local noteOffCommand = 0x80 + channel
  local velocity = 0

  reaper.StuffMIDIMessage(virtualKeyboardMode, noteOffCommand, midiNote, velocity)
  registerInternalNoteEvent(midiNote, false)
end

function stopNotesFromPlaying()

  local notesThatArePlaying = getNotesThatArePlaying()

  for noteIndex = 1, #notesThatArePlaying do
    stopNoteFromPlaying(notesThatArePlaying[noteIndex])
  end

  setNotesThatArePlaying({})
end
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/TK Scripts/Midi/TK_ChordGun"

function applyInversion(chord, inversionOverride)
  
  local chordLength = #chord
  if chordLength == 0 then return chord end

  local selectedScaleNote = getSelectedScaleNote()
  local chordInversionValue
  
  if inversionOverride then
    chordInversionValue = inversionOverride
  else
    chordInversionValue = getChordInversionState(selectedScaleNote)
  end
  
  local chord_ = {}
  for i, v in ipairs(chord) do chord_[i] = v end
  
  local fullOctaves = math.floor(chordInversionValue / chordLength)
  local remainingInversions = chordInversionValue % chordLength
  
  if fullOctaves ~= 0 then
     for i = 1, #chord_ do
       chord_[i] = chord_[i] + (fullOctaves * 12)
     end
  end
  
  if remainingInversions > 0 then
    for i = 1, remainingInversions do
      local r = table.remove(chord_, 1)
      r = r + 12
      table.insert(chord_, #chord_ + 1, r )
    end
  elseif remainingInversions < 0 then
    for i = 1, math.abs(remainingInversions) do
      local r = table.remove(chord_)
      r = r - 12
      table.insert(chord_, 1, r)
    end
  end
    
  return chord_
end

function getChordNotesArray(root, chord, octave, inversionOverride)

  local chordLength = 0
  local chordNotesArray = {}
  local chordPattern = chord["pattern"]
  for n = 0, #chordPattern-1 do
    if chordPattern:sub(n+1, n+1) == '1' then
      chordLength = chordLength + 1
      
      local noteValue = root + n + ((octave+1) * 12) - 1
      table.insert(chordNotesArray, noteValue)
    end
  end
  
  chordNotesArray = applyInversion(chordNotesArray, inversionOverride)
  
  local notesToDrop = {}
  if #chordNotesArray >= 2 and voicingState.drop2 then
    table.insert(notesToDrop, chordNotesArray[#chordNotesArray - 1])
  end
  if #chordNotesArray >= 3 and voicingState.drop3 then
    table.insert(notesToDrop, chordNotesArray[#chordNotesArray - 2])
  end
  
  for _, dropVal in ipairs(notesToDrop) do
    for i, noteVal in ipairs(chordNotesArray) do
      if noteVal == dropVal then
        chordNotesArray[i] = chordNotesArray[i] - 12
        break
      end
    end
  end
  
  if voicingState.bass1 == true then
    local bassNote = root + ((octave + 1 - 1) * 12) - 1
    table.insert(chordNotesArray, 1, bassNote)
  end
  if voicingState.bass2 == true then
    local bassNote = root + ((octave + 1 - 2) * 12) - 1
    table.insert(chordNotesArray, 1, bassNote)
  end
  
  local uniqueNotes = {}
  local seen = {}
  for _, v in ipairs(chordNotesArray) do
    if not seen[v] then
       table.insert(uniqueNotes, v)
       seen[v] = true
    end
  end
  chordNotesArray = uniqueNotes
  
  table.sort(chordNotesArray)
  
  return chordNotesArray
end
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/TK Scripts/Midi/TK_ChordGun"

local function getArpDelaySeconds()
    if arpSpeedMode == "ms" then
        return arpSpeedMs / 1000.0
    else
        local qn = 0.5
        if arpGrid == "1/4" then qn = 1.0
        elseif arpGrid == "1/8" then qn = 0.5
        elseif arpGrid == "1/16" then qn = 0.25
        elseif arpGrid == "1/32" then qn = 0.125
        elseif arpGrid == "1/64" then qn = 0.0625
        end
        
        local bpm = reaper.Master_GetTempo()
        return (60.0 / bpm) * qn
    end
end

local function getArpOffsetPPQ()
    local take = activeTake()
    if not take then return 0 end
    
    local ppqPerBeat = reaper.MIDI_GetPPQPosFromProjQN(take, 1) - reaper.MIDI_GetPPQPosFromProjQN(take, 0)
    
    if arpSpeedMode == "ms" then
        local bpm = reaper.Master_GetTempo()
        return (arpSpeedMs / 1000.0) * (bpm / 60.0) * ppqPerBeat
    else
        local qn = 0.5
        if arpGrid == "1/4" then qn = 1.0
        elseif arpGrid == "1/8" then qn = 0.5
        elseif arpGrid == "1/16" then qn = 0.25
        elseif arpGrid == "1/32" then qn = 0.125
        elseif arpGrid == "1/64" then qn = 0.0625
        end
        
        return qn * ppqPerBeat
    end
end

function insertMidiNote(note, keepNotesSelected, selectedChord, noteIndex)

  local startPosition = getCursorPositionPPQ()
	

	if strumEnabled then
		local ppq = reaper.MIDI_GetPPQPosFromProjQN(activeTake(), 0)
		local oneBeatInPPQ = (ppq + 1) - ppq
		local strumOffsetPPQ = (strumDelayMs / 1000.0) * (oneBeatInPPQ * 2)
		startPosition = startPosition + ((noteIndex - 1) * strumOffsetPPQ)
	elseif arpEnabled then
		local arpOffsetPPQ = getArpOffsetPPQ()
		startPosition = startPosition + ((noteIndex - 1) * arpOffsetPPQ)
	end

	local endPosition = nil
	local velocity = nil
	local channel = nil
	local muteState = nil
	
	if keepNotesSelected then

		local numberOfSelectedNotes = #selectedChord.selectedNotes

		if noteIndex > numberOfSelectedNotes then
			endPosition = selectedChord.selectedNotes[numberOfSelectedNotes].endPosition
			velocity = selectedChord.selectedNotes[numberOfSelectedNotes].velocity
			channel = selectedChord.selectedNotes[numberOfSelectedNotes].channel
			muteState = selectedChord.selectedNotes[numberOfSelectedNotes].muteState
		else
			endPosition = selectedChord.selectedNotes[noteIndex].endPosition
			velocity = selectedChord.selectedNotes[noteIndex].velocity
			channel = selectedChord.selectedNotes[noteIndex].channel
			muteState = selectedChord.selectedNotes[noteIndex].muteState
		end
		

		if strumEnabled then
			local ppq = reaper.MIDI_GetPPQPosFromProjQN(activeTake(), 0)
			local oneBeatInPPQ = (ppq + 1) - ppq
			local strumOffsetPPQ = (strumDelayMs / 1000.0) * (oneBeatInPPQ * 2)
			endPosition = endPosition + ((noteIndex - 1) * strumOffsetPPQ)
		elseif arpEnabled then
			local arpOffsetPPQ = getArpOffsetPPQ()
			endPosition = endPosition + ((noteIndex - 1) * arpOffsetPPQ)
		end
		
	else
		endPosition = getMidiEndPositionPPQ()
		

		if strumEnabled then
			local ppq = reaper.MIDI_GetPPQPosFromProjQN(activeTake(), 0)
			local oneBeatInPPQ = (ppq + 1) - ppq
			local strumOffsetPPQ = (strumDelayMs / 1000.0) * (oneBeatInPPQ * 2)
			endPosition = endPosition + ((noteIndex - 1) * strumOffsetPPQ)
		elseif arpEnabled then
			local arpOffsetPPQ = getArpOffsetPPQ()
			endPosition = endPosition + ((noteIndex - 1) * arpOffsetPPQ)
		end
		
		velocity = getCurrentVelocity()
		channel = getCurrentNoteChannel()
		muteState = false
	end

	local noSort = false

	reaper.MIDI_InsertNote(activeTake(), keepNotesSelected, muteState, startPosition, endPosition, channel, note, velocity, noSort)
end
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/TK Scripts/Midi/TK_ChordGun"

local function playScaleChord(chordNotesArray, velocity)

  stopNotesFromPlaying()
  
  if strumEnabled then

    local delaySeconds = strumDelayMs / 1000.0
    
    for noteIndex = 1, #chordNotesArray do
      playMidiNote(chordNotesArray[noteIndex], velocity)
      

      if noteIndex < #chordNotesArray then
        local startTime = reaper.time_precise()
        local targetTime = startTime + delaySeconds
        

        while reaper.time_precise() < targetTime do

        end
      end
    end
  elseif arpEnabled then

    local delaySeconds = getArpDelaySeconds()
    
    for noteIndex = 1, #chordNotesArray do
      playMidiNote(chordNotesArray[noteIndex], velocity)
      

      if noteIndex < #chordNotesArray then
        local startTime = reaper.time_precise()
        local targetTime = startTime + delaySeconds
        

        while reaper.time_precise() < targetTime do

        end
      end
    end
  else

    for noteIndex = 1, #chordNotesArray do
      playMidiNote(chordNotesArray[noteIndex], velocity)
    end
  end

  setNotesThatArePlaying(chordNotesArray) 
end


function addChordToProgression(scaleNoteIndex, chordTypeIndex, chordText, targetSlotOverride, octave, inversion)
  local targetSlot = targetSlotOverride
  

  if not targetSlot then
    for i = 1, maxProgressionSlots do
      if not chordProgression[i] then
        targetSlot = i
        break
      end
    end
  end
  
  if targetSlot and targetSlot >= 1 and targetSlot <= maxProgressionSlots then
    local currentSlot = chordProgression[targetSlot] or {}
    
    chordProgression[targetSlot] = {
      scaleNoteIndex = scaleNoteIndex,
      chordTypeIndex = chordTypeIndex,
      text = chordText,
      beats = currentSlot.beats or 1,
      repeats = currentSlot.repeats or 1,
      octave = octave or getOctave(),
      inversion = inversion
    }
  end
end

function playChordFromSlot(slotIndex)

  local slot = chordProgression[slotIndex]
  if not slot then return end
  

  stopAllNotesFromPlaying()
  

  local root = scaleNotes[slot.scaleNoteIndex]
  local chordData = scaleChords[slot.scaleNoteIndex][slot.chordTypeIndex]
  local octave = slot.octave or getOctave()
  
  local inversionOverride = slot.inversion
  if voiceLeadingEnabled then
     inversionOverride = getBestVoiceLeadingInversion(root, chordData, octave)
  end
  
  local notes = getChordNotesArray(root, chordData, octave, inversionOverride)
  if voiceLeadingEnabled then lastPlayedNotes = notes end
  
  notes = applyArpPattern(notes)
  

  if strumEnabled then
    local delaySeconds = strumDelayMs / 1000.0
    for noteIndex = 1, #notes do
        playMidiNote(notes[noteIndex])
        if noteIndex < #notes then
            local startTime = reaper.time_precise()
            local targetTime = startTime + delaySeconds
            while reaper.time_precise() < targetTime do end
        end
    end
  elseif arpEnabled then
    local delaySeconds = getArpDelaySeconds()
    for noteIndex = 1, #notes do
        playMidiNote(notes[noteIndex])
        if noteIndex < #notes then
            local startTime = reaper.time_precise()
            local targetTime = startTime + delaySeconds
            while reaper.time_precise() < targetTime do end
        end
    end
  else
      for noteIndex, note in ipairs(notes) do
        playMidiNote(note)
      end
  end
end

function clearChordProgression()
  chordProgression = {}
  progressionPlaying = false
  currentProgressionIndex = 0
end

function removeChordFromProgression(index)

  if index > 0 and index <= maxProgressionSlots then
    chordProgression[index] = nil
  end
end

function exportProgressionToTrack()

  local hasChords = false
  for i = 1, progressionLength do
    if chordProgression[i] then hasChords = true break end
  end
  
  if not hasChords then
    reaper.ShowMessageBox("Progression is empty.", "Error", 0)
    return
  end

  reaper.Undo_BeginBlock()
  
  local track = nil
  local numTracks = reaper.CountTracks(0)
  
  -- Search for existing "Chords" track
  for i = 0, numTracks - 1 do
    local t = reaper.GetTrack(0, i)
    local retval, name = reaper.GetSetMediaTrackInfo_String(t, "P_NAME", "", false)
    if name == "Chords" then
      track = t
      break
    end
  end
  
  if not track then
    -- Create new track at top
    reaper.InsertTrackAtIndex(0, true)
    track = reaper.GetTrack(0, 0)
    reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "Chords", true)
    reaper.SetMediaTrackInfo_Value(track, "B_HEIGHTLOCK", 1)
  end

  reaper.Main_OnCommand(40297, 0) -- Unselect all tracks
  reaper.SetTrackSelected(track, true)
  
  local currentPos = reaper.GetCursorPosition()
  local currentQN = reaper.TimeMap2_timeToQN(0, currentPos)
  
  for i = 1, progressionLength do
    local slot = chordProgression[i]
    
    if slot then
      local beats = slot.beats or 1
      local repeats = slot.repeats or 1
      local totalBeats = beats * repeats
      
      local startSec = reaper.TimeMap2_QNToTime(0, currentQN)
      local endQN = currentQN + totalBeats
      local endSec = reaper.TimeMap2_QNToTime(0, endQN)
      local length = endSec - startSec
      

      local item = reaper.AddMediaItemToTrack(track)
      reaper.SetMediaItemPosition(item, startSec, false)
      reaper.SetMediaItemLength(item, length, false)
      

      reaper.GetSetMediaItemInfo_String(item, "P_NOTES", slot.text, true)    
      
      -- Enable "Stretch to fit" for text (IMGRESOURCEFLAGS 2)
      local retval, chunk = reaper.GetItemStateChunk(item, "", false)
      if retval then
        if chunk:match("IMGRESOURCEFLAGS") then
           chunk = chunk:gsub("IMGRESOURCEFLAGS %d+", "IMGRESOURCEFLAGS 2")
        else
           chunk = chunk:gsub(">$", "IMGRESOURCEFLAGS 2\n>")
        end
        reaper.SetItemStateChunk(item, chunk, false)
      end

      reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", reaper.ColorToNative(77, 166, 255)|0x1000000)
      reaper.SetMediaItemInfo_Value(item, "C_LOCK", 1)
      
      currentQN = endQN
    else

      currentQN = currentQN + 1
    end
  end
  
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Export Chords to Track", -1)
end

function exportProgressionToMarkers()

  local hasChords = false
  for i = 1, progressionLength do
    if chordProgression[i] then hasChords = true break end
  end
  
  if not hasChords then
    reaper.ShowMessageBox("Progression is empty.", "Error", 0)
    return
  end

  reaper.Undo_BeginBlock()
  
  local currentPos = reaper.GetCursorPosition()
  local currentQN = reaper.TimeMap2_timeToQN(0, currentPos)
  
  for i = 1, progressionLength do
    local slot = chordProgression[i]
    
    if slot then
      local beats = slot.beats or 1
      local repeats = slot.repeats or 1
      local totalBeats = beats * repeats
      
      local startSec = reaper.TimeMap2_QNToTime(0, currentQN)
      local endQN = currentQN + totalBeats
      local endSec = reaper.TimeMap2_QNToTime(0, endQN)
      

      reaper.AddProjectMarker(0, true, startSec, endSec, slot.text, -1)
      
      currentQN = endQN
    else
      currentQN = currentQN + 1
    end
  end
  
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Export Chords to Markers", -1)
end

function generateMelodyFromProgression()

  local hasChords = false
  for i = 1, progressionLength do
    if chordProgression[i] then hasChords = true break end
  end
  
  if not hasChords then
    reaper.ShowMessageBox("Progression is empty.", "Error", 0)
    return
  end

  -- 1. Try Last Touched Track
  local track = reaper.GetLastTouchedTrack()
  
  -- 2. If no last touched, try First Selected Track
  if not track then
      track = reaper.GetSelectedTrack(0, 0)
  end
  
  -- 3. If still no track, ask user confirmation
  if not track then
    local result = reaper.ShowMessageBox("No track selected.\n\nCreate a new track for the melody?", "Create Melody Track", 4)
    if result ~= 6 then -- 6 = Yes, 7 = No
        return 
    end
  end

  reaper.Undo_BeginBlock()
  
  -- If track is nil here, it means user clicked "Yes" to create a new one
  if not track then
    local numTracks = reaper.CountTracks(0)
    reaper.InsertTrackAtIndex(numTracks, true) -- Insert at end
    track = reaper.GetTrack(0, numTracks)
    reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "Melody", true)
    
    reaper.Main_OnCommand(40297, 0) -- Unselect all
    reaper.SetTrackSelected(track, true)
    reaper.Main_OnCommand(40000, 0) -- Insert item if needed (handled later)
  end
  

  local totalBeats = 0
  for i = 1, progressionLength do
    local slot = chordProgression[i]
    if slot then
      totalBeats = totalBeats + (slot.beats * slot.repeats)
    else
      totalBeats = totalBeats + 1
    end
  end
  
  local startPos = reaper.GetCursorPosition()
  local startQN = reaper.TimeMap2_timeToQN(0, startPos)
  local endQN = startQN + totalBeats
  local endPos = reaper.TimeMap2_QNToTime(0, endQN)
  

  local item = reaper.CreateNewMIDIItemInProj(track, startPos, endPos, false)
  local take = nil
  if item and reaper.ValidatePtr(item, "MediaItem*") then
    take = reaper.GetActiveTake(item)
  end

  if not take then
    reaper.ShowMessageBox("Failed to create MIDI item.", "Error", 0)
    reaper.Undo_EndBlock("Generate Melody", -1)
    return
  end
  
  local currentQN = startQN
  local lastNote = -1
  local baseOctave = melodySettings.octave
  

  for i = 1, progressionLength do
    local slot = chordProgression[i]
    
    if slot then
      local root = scaleNotes[slot.scaleNoteIndex]
      local chordData = scaleChords[slot.scaleNoteIndex][slot.chordTypeIndex]
      

      local allNotes = {}
      

      local chordNotes = getChordNotesArray(root, chordData, baseOctave)
      local chordNotesHigh = getChordNotesArray(root, chordData, baseOctave + 1)
      local safeNotes = {}
      for _, n in ipairs(chordNotes) do table.insert(safeNotes, n) end
      for _, n in ipairs(chordNotesHigh) do table.insert(safeNotes, n) end
      

      local riskyNotes = {}
      if melodySettings.useScaleNotes then
        for n = 1, #scaleNotes do

          local normalizedNote = scaleNotes[n] % 12
          local noteVal = normalizedNote + ((baseOctave + 1) * 12)
          table.insert(riskyNotes, noteVal)
          table.insert(riskyNotes, noteVal + 12)
        end
      end
      
      local slotDuration = slot.beats * slot.repeats
      local slotEndQN = currentQN + slotDuration
      

      while currentQN < slotEndQN - 0.01 do

        local r = math.random()
        local dur = 1.0
        
        if melodySettings.density == 1 then
          if r < 0.6 then dur = 1.0
          elseif r < 0.9 then dur = 2.0
          else dur = 0.5
          end
        elseif melodySettings.density == 3 then
          if r < 0.5 then dur = 0.5
          elseif r < 0.8 then dur = 0.25
          else dur = 1.0
          end
        else
          if r < 0.4 then dur = 0.5
          elseif r < 0.8 then dur = 1.0
          else dur = 2.0
          end
        end
        

        if currentQN + dur > slotEndQN then dur = slotEndQN - currentQN end
        

        local note
        

        local poolToUse = safeNotes
        if melodySettings.useScaleNotes and #riskyNotes > 0 then


           if math.random() < 0.3 then
              poolToUse = riskyNotes
           end
        end
        
        if lastNote == -1 then
          note = poolToUse[math.random(#poolToUse)]
        else

          local candidates = {}
          for _, n in ipairs(poolToUse) do
            if math.abs(n - lastNote) <= 7 then
              table.insert(candidates, n)
            end
          end
          
          if #candidates > 0 then
            note = candidates[math.random(#candidates)]
          else
            note = poolToUse[math.random(#poolToUse)]
          end
        end
        

        local startPPQ = reaper.MIDI_GetPPQPosFromProjQN(take, currentQN)
        local endPPQ = reaper.MIDI_GetPPQPosFromProjQN(take, currentQN + dur)
        local vel = math.random(85, 110)
        
        reaper.MIDI_InsertNote(take, false, false, startPPQ, endPPQ, 0, note, vel, true)
        
        lastNote = note
        currentQN = currentQN + dur
      end
    else

      currentQN = currentQN + 1
    end
  end
  
  reaper.MIDI_Sort(take)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Generate Melody", -1)
end

function insertProgressionToMIDI()

  

  local take = activeTake()
  
  if not take then

    local track = reaper.GetSelectedTrack(0, 0)
    if track then

      local totalBeats = 0
      for i = 1, progressionLength do
        if chordProgression[i] then
          local beats = chordProgression[i].beats or 1
          local repeats = chordProgression[i].repeats or 1
          totalBeats = totalBeats + (beats * repeats)
        else
          totalBeats = totalBeats + 1
        end
      end
      
      if totalBeats == 0 then totalBeats = 4 end
      
      local startPos = reaper.GetCursorPosition()
      local startQN = reaper.TimeMap2_timeToQN(0, startPos)
      local endQN = startQN + totalBeats
      local endPos = reaper.TimeMap2_QNToTime(0, endQN)
      
      local item = reaper.CreateNewMIDIItemInProj(track, startPos, endPos, false)
      if item then
        reaper.SetMediaItemSelected(item, true)
        take = reaper.GetActiveTake(item)
      end
    end
  end

  if not take then
    reaper.ShowMessageBox("No active MIDI take found and no track selected.", "Error", 0)
    return
  end
  

  local hasChords = false
  for i = 1, progressionLength do
    if chordProgression[i] then
      hasChords = true
      break
    end
  end
  
  if not hasChords then
    reaper.ShowMessageBox("Progression is empty. Add some chords first!", "Error", 0)
    return
  end
  

  local startPPQ = getCursorPositionPPQ(take)
  local startQN = reaper.MIDI_GetProjQNFromPPQPos(take, startPPQ)
  local testPPQ = reaper.MIDI_GetPPQPosFromProjQN(take, startQN + 1.0)
  local oneBeatInPPQ = testPPQ - startPPQ
  
  local currentPPQ = startPPQ
  local velocity = getCurrentVelocity()
  local channel = getCurrentNoteChannel()
  
  reaper.Undo_BeginBlock()
  reaper.MIDI_DisableSort(take)
  
  local totalNotesInserted = 0
  

  for slotIndex = 1, progressionLength do
    local slot = chordProgression[slotIndex]
    
    if slot then

      local root = scaleNotes[slot.scaleNoteIndex]
      local chordData = scaleChords[slot.scaleNoteIndex][slot.chordTypeIndex]
      local octave = slot.octave or getOctave()
      
      local inversionOverride = slot.inversion
      if voiceLeadingEnabled and not inversionOverride then
         inversionOverride = getBestVoiceLeadingInversion(root, chordData, octave)
      end
      
      local notes = getChordNotesArray(root, chordData, octave, inversionOverride)
      if voiceLeadingEnabled then lastPlayedNotes = notes end
      
      notes = applyArpPattern(notes)
      
      local beats = slot.beats or 1
      local repeats = slot.repeats or 1
      

      for repeatIndex = 1, repeats do

        local noteDurationPPQ = oneBeatInPPQ * beats
        

        for noteIndex, note in ipairs(notes) do
          local noteStartPPQ = currentPPQ
          local noteEndPPQ = currentPPQ + noteDurationPPQ
          

          if strumEnabled then
            local strumOffsetPPQ = (strumDelayMs / 1000.0) * (oneBeatInPPQ * 2)
            noteStartPPQ = noteStartPPQ + ((noteIndex - 1) * strumOffsetPPQ)
            noteEndPPQ = noteEndPPQ + ((noteIndex - 1) * strumOffsetPPQ)
          elseif arpEnabled then
            local arpOffsetPPQ = getArpOffsetPPQ()
            noteStartPPQ = noteStartPPQ + ((noteIndex - 1) * arpOffsetPPQ)
            noteEndPPQ = noteEndPPQ + ((noteIndex - 1) * arpOffsetPPQ)
          end
          
          local success = reaper.MIDI_InsertNote(take, false, false, noteStartPPQ, noteEndPPQ, channel, note, velocity, true)
          if success then
            totalNotesInserted = totalNotesInserted + 1
          end
        end
        

        currentPPQ = currentPPQ + noteDurationPPQ
      end
    else

      currentPPQ = currentPPQ + oneBeatInPPQ
    end
  end
  
  reaper.MIDI_Sort(take)
  reaper.Undo_EndBlock("Insert Chord Progression", -1)
  

  reaper.MarkProjectDirty(0)
  reaper.UpdateArrange()
  reaper.UpdateTimeline()
  
  local mediaItem = reaper.GetMediaItemTake_Item(take)
  if mediaItem then
    reaper.UpdateItemInProject(mediaItem)
  end
  

  if not activeMidiEditor() then
    reaper.Main_OnCommand(40289, 0)
  end
end


local presetFolder = reaper.GetResourcePath() .. "/Scripts/TK Scripts/Midi/TK_ChordGun/Presets/"

function ensurePresetFolderExists()

  local result = reaper.RecursiveCreateDirectory(presetFolder, 0)
  return result ~= 0
end

function saveProgressionPreset()
  ensurePresetFolderExists()
  

  local hasChords = false
  for i = 1, maxProgressionSlots do
    if chordProgression[i] then
      hasChords = true
      break
    end
  end
  
  if not hasChords then
    reaper.ShowMessageBox("Progression is empty. Nothing to save!", "Error", 0)
    return
  end
  

  local retval, presetName = reaper.GetUserInputs("Save Progression Preset", 1, "Preset Name:,extrawidth=100", "")
  if not retval or presetName == "" then return end
  

  presetName = presetName:gsub("[^%w%s%-_]", "")
  
  local filePath = presetFolder .. presetName .. ".txt"
  local file = io.open(filePath, "w")
  
  if not file then
    reaper.ShowMessageBox("Could not create preset file!", "Error", 0)
    return
  end
  


  for i = 1, maxProgressionSlots do
    if chordProgression[i] then
      local slot = chordProgression[i]
      local octave = slot.octave or ""
      local inversion = slot.inversion or ""
      file:write(slot.scaleNoteIndex .. "," .. slot.chordTypeIndex .. "," .. slot.text .. "," .. slot.beats .. "," .. slot.repeats .. "," .. octave .. "," .. inversion .. "\n")
    else
      file:write("\n")
    end
  end
  

  file:write("LENGTH:" .. progressionLength .. "\n")
  

  file:write("SCALE:" .. getScaleTonicNote() .. "," .. getScaleType() .. "\n")
  
  file:close()
  reaper.ShowMessageBox("Preset '" .. presetName .. "' saved!", "Success", 0)
end

function getAvailablePresets()
  ensurePresetFolderExists()
  
  local presets = {}
  local i = 0
  
  repeat
    local file = reaper.EnumerateFiles(presetFolder, i)
    if file and file:match("%.txt$") then
      local presetName = file:gsub("%.txt$", "")
      table.insert(presets, presetName)
    end
    i = i + 1
  until not file
  
  return presets
end

function loadProgressionPreset(presetName)
  local filePath = presetFolder .. presetName .. ".txt"
  local file = io.open(filePath, "r")
  
  if not file then
    reaper.ShowMessageBox("Could not open preset file!", "Error", 0)
    return
  end
  

  chordProgression = {}
  

  local slotIndex = 1
  for line in file:lines() do
    if line:match("^LENGTH:") then

      local length = tonumber(line:match("LENGTH:(%d+)"))
      if length then
        progressionLength = length
      end
    elseif line:match("^SCALE:") then

      local tonic, scaleTypeIdx = line:match("SCALE:(%d+),(%d+)")
      if tonic and scaleTypeIdx then
        local newTonic = tonumber(tonic)
        local newType = tonumber(scaleTypeIdx)
        

        setScaleTonicNote(newTonic)
        setScaleType(newType)
        

        local sysIdx, subIdx = getSystemIndicesFromScaleIndex(newType)
        setScaleSystemIndex(sysIdx)
        setScaleWithinSystemIndex(subIdx)
        

        setSelectedScaleNote(1)
        setChordText("")
        resetSelectedChordTypes()
        resetChordInversionStates()
        updateScaleData()
        updateScaleDegreeHeaders()
        

        guiShouldBeUpdated = true
      end
    elseif line ~= "" and slotIndex <= maxProgressionSlots then

      local scaleNoteIndex, chordTypeIndex, text, beats, repeats, octave, inversion = line:match("(%d+),(%d+),([^,]+),(%d+),(%d+),?([^,]*),?([^,]*)")
      if scaleNoteIndex then
        chordProgression[slotIndex] = {
          scaleNoteIndex = tonumber(scaleNoteIndex),
          chordTypeIndex = tonumber(chordTypeIndex),
          text = text,
          beats = tonumber(beats),
          repeats = tonumber(repeats),
          octave = tonumber(octave),
          inversion = tonumber(inversion)
        }
      end
      slotIndex = slotIndex + 1
    else

      slotIndex = slotIndex + 1
    end
  end
  
  file:close()
end

function showLoadPresetMenu()
  local presets = getAvailablePresets()
  
  if #presets == 0 then
    reaper.ShowMessageBox("No presets found!", "Info", 0)
    return
  end
  

  local menuStr = ""
  

  for i, preset in ipairs(presets) do
    menuStr = menuStr .. preset .. "|"
  end
  

  menuStr = menuStr .. ">Delete preset|"
  for i, preset in ipairs(presets) do
    menuStr = menuStr .. preset
    if i < #presets then
      menuStr = menuStr .. "|"
    end
  end
  
  local result = gfx.showmenu(menuStr)
  
  if result > 0 and result <= #presets then

    loadProgressionPreset(presets[result])
  elseif result > #presets then

    local deleteIndex = result - #presets
    if deleteIndex > 0 and deleteIndex <= #presets then
      local presetName = presets[deleteIndex]
      

      local confirm = reaper.ShowMessageBox("Delete preset '" .. presetName .. "'?", "Confirm Delete", 4)
      if confirm == 6 then
        local filePath = presetFolder .. presetName .. ".txt"
        local success = os.remove(filePath)
        if success then
          reaper.ShowMessageBox("Preset '" .. presetName .. "' deleted!", "Success", 0)
        else
          reaper.ShowMessageBox("Could not delete preset!", "Error", 0)
        end
      end
    end
  end
end

function showDeletePresetMenu()

  showLoadPresetMenu()
end

function applyProgressionTemplate(template)
  chordProgression = {}
  local numNotes = #scaleNotes
  
  for i, degree in ipairs(template.chords) do
    if i > maxProgressionSlots then break end
    
    local actualDegree = degree
    if actualDegree > numNotes then
      actualDegree = ((actualDegree - 1) % numNotes) + 1
    end
    
    if scaleNotes[actualDegree] then
      local chordTypeIndex = getSelectedChordType(actualDegree) or 1
      local chordData = scaleChords[actualDegree][chordTypeIndex]
      if chordData then
        local text = getScaleNoteName(actualDegree) .. chordData['display']
        chordProgression[i] = {
          scaleNoteIndex = actualDegree,
          chordTypeIndex = chordTypeIndex,
          text = text,
          beats = 1,
          repeats = 1,
          octave = getOctave(),
          inversion = getChordInversionState(actualDegree)
        }
      end
    end
  end
  
  progressionLength = math.min(#template.chords, maxProgressionSlots)
  guiShouldBeUpdated = true
end

function showTemplatesMenu()
  local templates = Data.progressionTemplates
  if not templates or #templates == 0 then return end
  
  local numNotes = #scaleNotes
  local menuStr = ""
  local menuItems = {}
  
  for catIdx, category in ipairs(templates) do
    local catAvailable = numNotes >= (category.minNotes or 7)
    
    if catAvailable then
      menuStr = menuStr .. ">" .. category.name .. "|"
      
      for progIdx, prog in ipairs(category.progressions) do
        menuStr = menuStr .. prog.name
        table.insert(menuItems, {catIdx = catIdx, progIdx = progIdx})
        menuStr = menuStr .. "|"
      end
      menuStr = menuStr .. "<"
    else
      menuStr = menuStr .. "#" .. category.name .. " (min " .. category.minNotes .. " notes)"
    end
    menuStr = menuStr .. "|"
  end
  
  local result = gfx.showmenu(menuStr)
  
  if result > 0 and menuItems[result] then
    local item = menuItems[result]
    local template = templates[item.catIdx].progressions[item.progIdx]
    applyProgressionTemplate(template)
  end
end

function randomizeProgression()
  -- Define weights for scale degrees (1-7)
  -- 1=I, 2=ii, 3=iii, 4=IV, 5=V, 6=vi, 7=vii
  -- Pop weights: I, IV, V, vi are most common.
  local weights = {
    {degree=1, weight=25}, -- Tonic
    {degree=4, weight=20}, -- Subdominant
    {degree=5, weight=20}, -- Dominant
    {degree=6, weight=20}, -- Submediant (relative minor)
    {degree=2, weight=10}, -- Supertonic
    {degree=3, weight=5},  -- Mediant
    {degree=7, weight=5}   -- Leading tone
  }
  
  -- Calculate total weight
  local totalWeight = 0
  for _, item in ipairs(weights) do
    totalWeight = totalWeight + item.weight
  end
  
  local filledAny = false
  
  -- Fill empty slots up to progressionLength
  for i = 1, progressionLength do
    local forceTonic = (i == 1 and randomizeStartWithTonic)
    
    if not chordProgression[i] or forceTonic then
      -- Pick random degree based on weight
      local selectedDegree = 1
      
      if forceTonic then
        selectedDegree = 1
      else
        local rnd = math.random(1, totalWeight)
        local currentWeight = 0
        
        for _, item in ipairs(weights) do
          currentWeight = currentWeight + item.weight
          if rnd <= currentWeight then
            selectedDegree = item.degree
            break
          end
        end
      end
      
      -- Ensure degree exists in current scale (some scales have fewer notes)
      if scaleNotes[selectedDegree] then
        -- Add chord (default chord type index 1)
        local chordTypeIndex = 1
        if randomizeUseSelectedChords then
            chordTypeIndex = getSelectedChordType(selectedDegree)
        end
        local chordData = scaleChords[selectedDegree][chordTypeIndex]
        if chordData then
           local text = getScaleNoteName(selectedDegree) .. chordData['display']
           addChordToProgression(selectedDegree, chordTypeIndex, text, i, getOctave(), getChordInversionState(selectedDegree))
           filledAny = true
        end
      end
    end
  end
  
  if filledAny then
    guiShouldBeUpdated = true
  end
end

function playProgressionChord(index)
  if index < 1 or index > #chordProgression then return end
  
  local chord = chordProgression[index]
  if not chord then return end
  
  if chord.scaleNoteIndex > #scaleNotes then return end
  if not scaleChords[chord.scaleNoteIndex] then return end
  
  lastPlayedScaleDegree = chord.scaleNoteIndex
  setSelectedScaleNote(chord.scaleNoteIndex)
  setSelectedChordType(chord.scaleNoteIndex, chord.chordTypeIndex)
  
  local root = scaleNotes[chord.scaleNoteIndex]
  local chordData = scaleChords[chord.scaleNoteIndex][chord.chordTypeIndex]
  local octave = chord.octave or getOctave()
  local inversion = chord.inversion
  
  local chordNotesArray = getChordNotesArray(root, chordData, octave, inversion)
  chordNotesArray = applyArpPattern(chordNotesArray)
  
  if strumEnabled then
    local delaySeconds = strumDelayMs / 1000.0
    for noteIndex = 1, #chordNotesArray do
      playMidiNote(chordNotesArray[noteIndex])
      if noteIndex < #chordNotesArray then
        local startTime = reaper.time_precise()
        local targetTime = startTime + delaySeconds
        while reaper.time_precise() < targetTime do end
      end
    end
  elseif arpEnabled then
    local delaySeconds = arpSpeedMs / 1000.0
    for noteIndex = 1, #chordNotesArray do
      playMidiNote(chordNotesArray[noteIndex])
      if noteIndex < #chordNotesArray then
        local startTime = reaper.time_precise()
        local targetTime = startTime + delaySeconds
        while reaper.time_precise() < targetTime do end
      end
    end
  else
    for noteIndex = 1, #chordNotesArray do
      playMidiNote(chordNotesArray[noteIndex])
    end
  end
  setNotesThatArePlaying(chordNotesArray)
  
  updateChordText(root, chordData, chordNotesArray)
end

function startProgressionPlayback()
  if #chordProgression == 0 then return end
  progressionPlaying = true
  currentProgressionIndex = 1
  progressionLastBeatTime = reaper.time_precise()
  playProgressionChord(1)
end

function stopProgressionPlayback()
  progressionPlaying = false
  currentProgressionIndex = 0
  stopNotesFromPlaying()
end

function updateProgressionPlayback()
  if not progressionPlaying then return end
  

  local hasChords = false
  for i = 1, maxProgressionSlots do
    if chordProgression[i] then
      hasChords = true
      break
    end
  end
  if not hasChords then return end
  
  local currentTime = reaper.time_precise()
  local bpm = reaper.Master_GetTempo()
  

  local currentSlotBeats = 1
  if chordProgression[currentProgressionIndex] then
    currentSlotBeats = chordProgression[currentProgressionIndex].beats or 1
  end
  
  local beatDuration = (60.0 / bpm) * currentSlotBeats
  
  if currentTime - progressionLastBeatTime >= beatDuration then

    local currentSlotRepeats = 1
    if chordProgression[currentProgressionIndex] then
      currentSlotRepeats = chordProgression[currentProgressionIndex].repeats or 1
    end
    
    currentProgressionRepeat = currentProgressionRepeat + 1
    

    if currentProgressionRepeat < currentSlotRepeats then

      progressionLastBeatTime = progressionLastBeatTime + beatDuration
      

      local oldNotes = getNotesThatArePlaying()
      for i = 1, #oldNotes do
        stopNoteFromPlaying(oldNotes[i])
      end
      
      local chord = chordProgression[currentProgressionIndex]
      if chord and chord.scaleNoteIndex <= #scaleNotes and scaleChords[chord.scaleNoteIndex] then
        local root = scaleNotes[chord.scaleNoteIndex]
        local chordData = scaleChords[chord.scaleNoteIndex][chord.chordTypeIndex]
        local octave = chord.octave or getOctave()
        local inversion = chord.inversion
        local newNotes = getChordNotesArray(root, chordData, octave, inversion)
        newNotes = applyArpPattern(newNotes)
        

        if strumEnabled then
          local delaySeconds = strumDelayMs / 1000.0
          for noteIndex = 1, #newNotes do
            playMidiNote(newNotes[noteIndex])
            if noteIndex < #newNotes then
              local startTime = reaper.time_precise()
              local targetTime = startTime + delaySeconds
              while reaper.time_precise() < targetTime do end
            end
          end
        elseif arpEnabled then
          local delaySeconds = arpSpeedMs / 1000.0
          for noteIndex = 1, #newNotes do
            playMidiNote(newNotes[noteIndex])
            if noteIndex < #newNotes then
              local startTime = reaper.time_precise()
              local targetTime = startTime + delaySeconds
              while reaper.time_precise() < targetTime do end
            end
          end
        else
          for i = 1, #newNotes do
            playMidiNote(newNotes[i])
          end
        end
        setNotesThatArePlaying(newNotes)
      end
      return
    end
    

    currentProgressionRepeat = 0
    currentProgressionIndex = currentProgressionIndex + 1
    if currentProgressionIndex > progressionLength then
      currentProgressionIndex = 1
    end
    

    progressionLastBeatTime = progressionLastBeatTime + beatDuration
    

    local oldNotes = getNotesThatArePlaying()
    for i = 1, #oldNotes do
      stopNoteFromPlaying(oldNotes[i])
    end
    

    local chord = chordProgression[currentProgressionIndex]
    if chord and chord.scaleNoteIndex <= #scaleNotes and scaleChords[chord.scaleNoteIndex] then

      setSelectedScaleNote(chord.scaleNoteIndex)
      setSelectedChordType(chord.scaleNoteIndex, chord.chordTypeIndex)
      
      local root = scaleNotes[chord.scaleNoteIndex]
      local chordData = scaleChords[chord.scaleNoteIndex][chord.chordTypeIndex]
      local octave = chord.octave or getOctave()
      local inversion = chord.inversion
      local newNotes = getChordNotesArray(root, chordData, octave, inversion)
      newNotes = applyArpPattern(newNotes)
      

      if strumEnabled then

        local delaySeconds = strumDelayMs / 1000.0
        
        for noteIndex = 1, #newNotes do
          playMidiNote(newNotes[noteIndex])
          

          if noteIndex < #newNotes then
            local startTime = reaper.time_precise()
            local targetTime = startTime + delaySeconds
            

            while reaper.time_precise() < targetTime do

            end
          end
        end
      elseif arpEnabled then

        local delaySeconds = arpSpeedMs / 1000.0
        
        for noteIndex = 1, #newNotes do
          playMidiNote(newNotes[noteIndex])
          

          if noteIndex < #newNotes then
            local startTime = reaper.time_precise()
            local targetTime = startTime + delaySeconds
            

            while reaper.time_precise() < targetTime do

            end
          end
        end
      else

        for i = 1, #newNotes do
          playMidiNote(newNotes[i])
        end
      end
      
      setNotesThatArePlaying(newNotes)
      updateChordText(root, chordData, newNotes)
    else

      setNotesThatArePlaying({})
    end
  end
end

function previewScaleChord(velocity)

  local scaleNoteIndex = getSelectedScaleNote()
  lastPlayedScaleDegree = scaleNoteIndex
  local chordTypeIndex = getSelectedChordType(scaleNoteIndex)

  local root = scaleNotes[scaleNoteIndex]
  local chord = scaleChords[scaleNoteIndex][chordTypeIndex]
  local octave = getOctave()

  local inversionOverride = nil

  if voiceLeadingEnabled then
     inversionOverride = getBestVoiceLeadingInversion(root, chord, octave)
  end

  local chordNotesArray = getChordNotesArray(root, chord, octave, inversionOverride)
  if voiceLeadingEnabled then lastPlayedNotes = chordNotesArray end
  
  chordNotesArray = applyArpPattern(chordNotesArray)
  playScaleChord(chordNotesArray, velocity)
  setNotesThatArePlaying(chordNotesArray)
  updateChordText(root, chord, chordNotesArray)
end

function insertScaleChord(chordNotesArray, keepNotesSelected, selectedChord)

  deleteExistingNotesInNextInsertionTimePeriod(keepNotesSelected, selectedChord)

  for noteIndex = 1, #chordNotesArray do
    insertMidiNote(chordNotesArray[noteIndex], keepNotesSelected, selectedChord, noteIndex)
  end

  moveCursor(keepNotesSelected, selectedChord)
end

local lastActiveTake = nil

function ensureActiveTake()

  -- Determine Target Track (Priority: Selected > Last Touched)
  local targetTrack = reaper.GetSelectedTrack(0, 0)
  if not targetTrack then
      targetTrack = reaper.GetLastTouchedTrack()
  end

  -- 1. Check activeTake() first (Standard REAPER behavior + MIDI Editor)
  local take = activeTake()
  if take then 
      local item = reaper.GetMediaItemTake_Item(take)
      if item then
          -- Check if this take is on the target track
          local itemTrack = reaper.GetMediaItem_Track(item)
          if itemTrack == targetTrack then
              reaper.SelectAllMediaItems(0, false)
              reaper.SetMediaItemSelected(item, true)
              reaper.UpdateArrange()
              lastActiveTake = take
              return take 
          end
      end
  end

  -- 2. Check Memory (Smart Append)
  -- Reuse if cursor is INSIDE or AT THE END of the item
  if lastActiveTake and reaper.ValidatePtr(lastActiveTake, "MediaItem_Take*") then
      local item = reaper.GetMediaItemTake_Item(lastActiveTake)
      local itemTrack = reaper.GetMediaItem_Track(item)
      
      if itemTrack == targetTrack then
          local itemStart = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
          local itemLen = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
          local itemEnd = itemStart + itemLen
          local cursorPos = reaper.GetCursorPosition()
          local tolerance = 0.001 

          -- Check if cursor is STRICTLY INSIDE the item bounds
          -- We exclude the END point to allow creating new items immediately after
          if cursorPos >= (itemStart - tolerance) and cursorPos < (itemEnd - tolerance) then
              reaper.SelectAllMediaItems(0, false)
              reaper.SetMediaItemSelected(item, true)
              reaper.UpdateArrange()
              return lastActiveTake
          end
      end
  end

  if not targetTrack then
    reaper.ShowMessageBox("No track selected.\nPlease select or touch a track to insert chords.", "Error", 0)
    return nil
  end

  local track = targetTrack

  local startPos = reaper.GetCursorPosition()
  
  local lengthTime
  local index = getNoteLengthIndex()
  local option = noteLengthOptions[index]
  
  if option and option.qn == -1 then
      local startLoop, endLoop = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
      if startLoop ~= endLoop then
          lengthTime = endLoop - startLoop
      else
          lengthTime = 2.0
      end
  elseif option and option.qn then
       local bpm = reaper.Master_GetTempo()
       lengthTime = (60/bpm) * option.qn
  else
       local bpm = reaper.Master_GetTempo()
       lengthTime = (60/bpm) * 4
  end
  
  if lengthTime < 1.0 then lengthTime = (60/reaper.Master_GetTempo()) * 4 end

  local endPos = startPos + lengthTime

  local item = reaper.CreateNewMIDIItemInProj(track, startPos, endPos, false)
  if item then
    reaper.SelectAllMediaItems(0, false)
    if reaper.ValidatePtr(item, "MediaItem*") then
      reaper.SetMediaItemSelected(item, true)
    end
    reaper.Main_OnCommand(40913, 0) -- Track: Vertical scroll selected tracks into view
    reaper.UpdateArrange()
    
    if reaper.ValidatePtr(item, "MediaItem*") then
      local newTake = reaper.GetActiveTake(item)
      lastActiveTake = newTake
      return newTake
    end
  end

  return nil
end

function playOrInsertScaleChord(actionDescription)

  local scaleNoteIndex = getSelectedScaleNote()
  local chordTypeIndex = getSelectedChordType(scaleNoteIndex)

  local root = scaleNotes[scaleNoteIndex]
  local chord = scaleChords[scaleNoteIndex][chordTypeIndex]
  local octave = getOctave()
  
  local chordNotesArray = getChordNotesArray(root, chord, octave)
  chordNotesArray = applyArpPattern(chordNotesArray)

  if ensureActiveTake() and notCurrentlyRecording() then

    startUndoBlock()

      if thereAreNotesSelected() then 
        changeSelectedNotesToScaleChords(chordNotesArray)
      else
        insertScaleChord(chordNotesArray, false)
      end

    endUndoBlock(actionDescription)
    

    if not activeMidiEditor() then
      reaper.Main_OnCommand(40289, 0)
    end
  end

  playScaleChord(chordNotesArray)
  updateChordText(root, chord, chordNotesArray)
end
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/TK Scripts/Midi/TK_ChordGun"


local function playScaleNote(noteValue)

  stopNotesFromPlaying()
  playMidiNote(noteValue)
  setNotesThatArePlaying({noteValue})
  setChordText("")
end


function insertScaleNote(noteValue, keepNotesSelected, selectedChord)

	deleteExistingNotesInNextInsertionTimePeriod(keepNotesSelected, selectedChord)

	local noteIndex = 1
	insertMidiNote(noteValue, keepNotesSelected, selectedChord, noteIndex)
	moveCursor(keepNotesSelected, selectedChord)
end

function previewScaleNote(octaveAdjustment)

  local scaleNoteIndex = getSelectedScaleNote()

  local root = scaleNotes[scaleNoteIndex]
  local octave = getOctave()
  local noteValue = root + ((octave+1+octaveAdjustment) * 12) - 1

  playScaleNote(noteValue)
end

function playOrInsertScaleNote(octaveAdjustment, actionDescription)

	local scaleNoteIndex = getSelectedScaleNote()

  local root = scaleNotes[scaleNoteIndex]
  local octave = getOctave()
  local noteValue = root + ((octave+1+octaveAdjustment) * 12) - 1

  if ensureActiveTake() and notCurrentlyRecording() then

  	startUndoBlock()

		  if thereAreNotesSelected() then 
		    changeSelectedNotesToScaleNotes(noteValue)
		  else
		    insertScaleNote(noteValue, false)
		  end

		endUndoBlock(actionDescription)
    

    if not activeMidiEditor() then
      reaper.Main_OnCommand(40289, 0)
    end
  end

	playScaleNote(noteValue)
end
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/TK Scripts/Midi/TK_ChordGun"

SelectedNote = {}
SelectedNote.__index = SelectedNote

function SelectedNote:new(endPosition, velocity, channel, muteState, pitch)
  local self = {}
  setmetatable(self, SelectedNote)

  self.endPosition = endPosition
  self.velocity = velocity
  self.channel = channel
  self.muteState = muteState
  self.pitch = pitch

  return self
end

SelectedChord = {}
SelectedChord.__index = SelectedChord

function SelectedChord:new(startPosition, endPosition, velocity, channel, muteState, pitch)
  local self = {}
  setmetatable(self, SelectedChord)

  self.startPosition = startPosition
  self.longestEndPosition = endPosition

  self.selectedNotes = {}
  table.insert(self.selectedNotes, SelectedNote:new(endPosition, velocity, channel, muteState, pitch))

  return self
end



local function noteStartPositionDoesNotExist(selectedChords, startPositionArg)

	for index, selectedChord in pairs(selectedChords) do

		if selectedChord.startPosition == startPositionArg then
			return false
		end
	end

	return true
end

local function updateSelectedChord(selectedChords, startPositionArg, endPositionArg, velocityArg, channelArg, muteStateArg, pitchArg)

	for index, selectedChord in pairs(selectedChords) do

		if selectedChord.startPosition == startPositionArg then

			table.insert(selectedChord.selectedNotes, SelectedNote:new(endPositionArg, velocityArg, channelArg, muteStateArg, pitchArg))

			if endPositionArg > selectedChord.longestEndPosition then
				selectedChord.longestEndPosition = endPositionArg
			end

		end
	end
end

local function getSelectedChords()

	local numberOfNotes = getNumberOfNotes()
	local selectedChords = {}

	for noteIndex = 0, numberOfNotes-1 do

		local _, noteIsSelected, muteState, noteStartPositionPPQ, noteEndPositionPPQ, channel, pitch, velocity = reaper.MIDI_GetNote(activeTake(), noteIndex)

		if noteIsSelected then

			if noteStartPositionDoesNotExist(selectedChords, noteStartPositionPPQ) then
				table.insert(selectedChords, SelectedChord:new(noteStartPositionPPQ, noteEndPositionPPQ, velocity, channel, muteState, pitch))
			else
				updateSelectedChord(selectedChords, noteStartPositionPPQ, noteEndPositionPPQ, velocity, channel, muteState, pitch)
			end
		end
	end

	for selectedChordIndex = 1, #selectedChords do
		table.sort(selectedChords[selectedChordIndex].selectedNotes, function(a,b) return a.pitch < b.pitch end)
	end

	return selectedChords
end

local function deleteSelectedNotes()

	local numberOfNotes = getNumberOfNotes()

	for noteIndex = numberOfNotes-1, 0, -1 do

		local _, noteIsSelected = reaper.MIDI_GetNote(activeTake(), noteIndex)
	
		if noteIsSelected then
			deleteNote(noteIndex)
		end
	end
end

local function setEditCursorTo(arg)

	local cursorPosition = reaper.MIDI_GetProjTimeFromPPQPos(activeTake(), arg)
	setEditCursorPosition(cursorPosition)
end

function changeSelectedNotesToScaleChords(chordNotesArray)

	local selectedChords = getSelectedChords()
	deleteSelectedNotes()
	
	for i = 1, #selectedChords do
		setEditCursorTo(selectedChords[i].startPosition)
		insertScaleChord(chordNotesArray, true, selectedChords[i])
	end
end

function changeSelectedNotesToScaleNotes(noteValue)

	local selectedChords = getSelectedChords()
	deleteSelectedNotes()

	for i = 1, #selectedChords do
		setEditCursorTo(selectedChords[i].startPosition)
		insertScaleNote(noteValue, true, selectedChords[i])
	end
end
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/TK Scripts/Midi/TK_ChordGun"

scaleNotes = {}
scaleChords = {}

scalePattern = nil

chordButtons = {}

function getNotesString(chordNotesArray)

  local notesString = ''
  for i, note in ipairs(chordNotesArray) do
        
    local noteName = getNoteName(note+1)
    
    if i ~= #chordNotesArray then
      notesString = notesString .. noteName .. ','
    else
      notesString = notesString .. noteName .. ''
    end
  end
  
  return notesString
end

--------------------------------------------------------------------------------

function updateScaleNotes()

  scaleNotes = {}

  local scaleNoteIndex = 1
  for note = getScaleTonicNote(), getScaleTonicNote() + 11 do
  
    if noteIsInScale(note) then
      scaleNotes[scaleNoteIndex] = note
      scaleNoteIndex = scaleNoteIndex + 1
    end
  end
end

function updateScaleChords()

  scaleChords = {}

  local scaleNoteIndex = 1
  for note = getScaleTonicNote(), getScaleTonicNote() + 11 do
  
    if noteIsInScale(note) then
      scaleChords[scaleNoteIndex] = getScaleChordsForRootNote(note)
      scaleNoteIndex = scaleNoteIndex + 1
    end
  end
end

function removeFlatsAndSharps(arg)
  return arg:gsub('b',''):gsub('#','')
end

function aNoteIsRepeated()

  local numberOfScaleNoteNames = 7
  local previousScaleNoteName = getScaleNoteName(numberOfScaleNoteNames)
  local scaleNoteName = nil

  for scaleDegree = 1,  numberOfScaleNoteNames do

    scaleNoteName = getScaleNoteName(scaleDegree)

    if removeFlatsAndSharps(scaleNoteName) == removeFlatsAndSharps(previousScaleNoteName) then
      return true
    end

    previousScaleNoteName = scaleNoteName
  end

  return false
end

function updateScaleNoteNames()
  
  local previousScaleNoteName = getSharpNoteName(getScaleTonicNote() + 11)
  local scaleNoteName = nil
  
  local scaleDegree = 1
  for note = getScaleTonicNote(), getScaleTonicNote() + 11 do
  
    if scalePattern[getNotesIndex(note)] then

      scaleNoteName = getSharpNoteName(note) 
      setScaleNoteName(scaleDegree, scaleNoteName)      
      scaleDegree = scaleDegree + 1
      previousScaleNoteName = scaleNoteName
    end
  end
  
  if aNoteIsRepeated() then
  
    local previousScaleNoteName = getFlatNoteName(getScaleTonicNote() + 11)
    local scaleNoteName = nil
    
    local scaleDegree = 1
    for note = getScaleTonicNote(), getScaleTonicNote() + 11 do
    
      if scalePattern[getNotesIndex(note)] then
            
        scaleNoteName = getFlatNoteName(note)        
        setScaleNoteName(scaleDegree, scaleNoteName)      
        scaleDegree = scaleDegree + 1
        previousScaleNoteName = scaleNoteName
      end
    end
  end
end

function updateScaleNotesText()
  
  local scaleNotesText = ''
  
  for i = 1, #scaleNotes do
    if scaleNotesText ~= '' then 
      scaleNotesText = scaleNotesText .. ', '
    end
    
    scaleNotesText = scaleNotesText .. getScaleNoteName(i)
  end

  setScaleNotesText(scaleNotesText)
end

function getChordInversionText(chordNotesArray)

  local selectedScaleNote = getSelectedScaleNote()
  local inversionValue = getChordInversionState(selectedScaleNote)
  
  if inversionValue == 0 then
    return ''
  end
  
  if math.fmod(inversionValue, #chordNotesArray) == 0 then
    return ''
  end
    
  return '/' .. getNoteName(chordNotesArray[1]+1)
end

function getChordInversionOctaveIndicator(numberOfChordNotes)

  local selectedScaleNote = getSelectedScaleNote()
  local inversionValue = getChordInversionState(selectedScaleNote)

  local octaveIndicator = nil
   
  if inversionValue > 0 then
  
    local offsetValue = math.floor(inversionValue / numberOfChordNotes)
    
    if offsetValue > 0 then
      return '+' .. offsetValue
    else
      return '+'
    end
  
  elseif inversionValue < 0 then
  
    local offsetValue = math.abs(math.ceil(inversionValue / numberOfChordNotes))
    
    if offsetValue > 0 then
      return '-' .. offsetValue
    else  
      return '-'
    end
  else
    return ''
  end  
end

function updateChordText(root, chord, chordNotesArray)
  
  local rootNoteName = getNoteName(root)
  local chordInversionText = getChordInversionText(chordNotesArray)
  local chordInversionOctaveIndicator = getChordInversionOctaveIndicator(#chordNotesArray)
  local chordString = rootNoteName .. chord["display"]
  local notesString = getNotesString(chordNotesArray)

  local chordTextValue = ''
  if string.match(chordInversionOctaveIndicator, "-") then
    chordTextValue = ("%s%12s%s%12s"):format(chordInversionOctaveIndicator, chordString, chordInversionText, notesString)
  elseif string.match(chordInversionOctaveIndicator, "+") then
    chordTextValue = ("%s%12s%s%12s%12s"):format('', chordString, chordInversionText, notesString, chordInversionOctaveIndicator)
  else
    chordTextValue = ("%s%12s%s%12s"):format('', chordString, chordInversionText, notesString)
  end

  setChordText(chordTextValue)
  
  showChordText()
end

function showChordText()

  local chordText = getChordText()
  reaper.Help_Set(chordText, false)
end

function updateScaleData()

  scalePattern = getScalePattern(getScaleTonicNote(), scales[getScaleType()])
  updateScaleNotes()
  updateScaleNoteNames()
  updateScaleNotesText()
  updateScaleChords()
  updateScaleDegreeHeaders()
  updateScaleFilterState()
end

function showScaleStatus()

  local scaleTonicText =  notes[getScaleTonicNote()]
  local scaleTypeText = scales[getScaleType()].name
  local scaleNotesText = getScaleNotesText()
  reaper.Help_Set(("%s %s: %s"):format(scaleTonicText, scaleTypeText, scaleNotesText), false)
end
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/TK Scripts/Midi/TK_ChordGun"

local function transposeSelectedNotes(numberOfSemitones)

  local numberOfNotes = getNumberOfNotes()

  for noteIndex = numberOfNotes-1, 0, -1 do

    local _, noteIsSelected, muteState, noteStartPositionPPQ, noteEndPositionPPQ, channel, pitch, velocity = reaper.MIDI_GetNote(activeTake(), noteIndex)
  
    if noteIsSelected then
      deleteNote(noteIndex)
      local noSort = false
      reaper.MIDI_InsertNote(activeTake(), noteIsSelected, muteState, noteStartPositionPPQ, noteEndPositionPPQ, channel, pitch+numberOfSemitones, velocity, noSort)
    end
  end
end

function transposeSelectedNotesUpOneOctave()
  transposeSelectedNotes(12)
end

function transposeSelectedNotesDownOneOctave()
  transposeSelectedNotes(-12)
end
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/TK Scripts/Midi/TK_ChordGun"

local function decrementChordInversion()

	local selectedScaleNote = getSelectedScaleNote()

  local chordInversionMin = getChordInversionMin()
  local chordInversion = getChordInversionState(selectedScaleNote)

  if chordInversion <= chordInversionMin then
    return
  end

  setChordInversionState(selectedScaleNote, chordInversion-1)
end

function decrementChordInversionAction()

	local actionDescription = "decrement chord inversion"
	decrementChordInversion()

	if thereAreNotesSelected() then
		playOrInsertScaleChord(actionDescription)
	else
		previewScaleChord()
	end
end

--

local function incrementChordInversion()

	local selectedScaleNote = getSelectedScaleNote()

  local chordInversionMax = getChordInversionMax()
  local chordInversion = getChordInversionState(selectedScaleNote)

  if chordInversion >= chordInversionMax then
    return
  end


  setChordInversionState(selectedScaleNote, chordInversion+1)
end

function incrementChordInversionAction()

	local actionDescription = "increment chord inversion"
	incrementChordInversion()

	if thereAreNotesSelected() then
		playOrInsertScaleChord(actionDescription)
	else
		previewScaleChord()
	end
end

--

local function decrementChordType()

	local selectedScaleNote = getSelectedScaleNote()
	local selectedChordType = getSelectedChordType(selectedScaleNote)

  if selectedChordType <= 1 then
    return
  end

  setSelectedChordType(selectedScaleNote, selectedChordType-1)
end

function decrementChordTypeAction()

	local actionDescription = "decrement chord type"
	decrementChordType()

	if thereAreNotesSelected() then
		playOrInsertScaleChord(actionDescription)
	else
		previewScaleChord()
	end
end

--

local function incrementChordType()

	local selectedScaleNote = getSelectedScaleNote()
	local selectedChordType = getSelectedChordType(selectedScaleNote)

  if selectedChordType >= #chords then
    return
  end

  setSelectedChordType(selectedScaleNote, selectedChordType+1)
end

function incrementChordTypeAction()

	local actionDescription = "increment chord type"
	incrementChordType()

	if thereAreNotesSelected() then
		playOrInsertScaleChord(actionDescription)
	else
		previewScaleChord()
	end
end

--

function playTonicNote()

  local root = scaleNotes[1]
  local octave = getOctave()
  local noteValue = root + ((octave+1) * 12) - 1

  stopNotesFromPlaying()
  playMidiNote(noteValue)
  setNotesThatArePlaying({noteValue})
end

local function decrementOctave()

  local octave = getOctave()

  if octave <= getOctaveMin() then
    return
  end

  setOctave(octave-1)
end

function decrementOctaveAction()

	decrementOctave()

	if thereAreNotesSelected() then
		startUndoBlock()
		transposeSelectedNotesDownOneOctave()
		endUndoBlock("decrement octave")
	else
		playTonicNote()
	end
end

--

local function incrementOctave()

  local octave = getOctave()

  if octave >= getOctaveMax() then
    return
  end

  setOctave(octave+1)
end

function incrementOctaveAction()

	incrementOctave()

	if thereAreNotesSelected() then
		startUndoBlock()
		transposeSelectedNotesUpOneOctave()
		endUndoBlock("increment octave")
	else
		playTonicNote()
	end
end

--

local function decrementScaleTonicNote()

	local scaleTonicNote = getScaleTonicNote()

	if scaleTonicNote <= 1 then
		return
	end

	setScaleTonicNote(scaleTonicNote-1)
end

function decrementScaleTonicNoteAction()

	decrementScaleTonicNote()

	setSelectedScaleNote(1)
	setChordText("")
	resetSelectedChordTypes()
	resetChordInversionStates()
	updateScaleData()
	updateScaleDegreeHeaders()
	showScaleStatus()
end

--

local function incrementScaleTonicNote()

	local scaleTonicNote = getScaleTonicNote()

	if scaleTonicNote >= #notes then
		return
	end

	setScaleTonicNote(scaleTonicNote+1)
end

function incrementScaleTonicNoteAction()

	incrementScaleTonicNote()

	setSelectedScaleNote(1)
	setChordText("")
	resetSelectedChordTypes()
	resetChordInversionStates()
	updateScaleData()
	updateScaleDegreeHeaders()
	showScaleStatus()
end

--

local function decrementScaleType()

	local scaleType = getScaleType()

	if scaleType <= 1 then
		return
	end

	setScaleType(scaleType-1)
	
end

function decrementScaleTypeAction()

	decrementScaleType()

	setSelectedScaleNote(1)
	setChordText("")
	resetSelectedChordTypes()
	resetChordInversionStates()
	updateScaleData()
	updateScaleDegreeHeaders()
	showScaleStatus()
end

--

local function incrementScaleType()

	local scaleType = getScaleType()

	if scaleType >= #scales then
		return
	end

	setScaleType(scaleType+1)
end

function incrementScaleTypeAction()

	incrementScaleType()

	setSelectedScaleNote(1)
	setChordText("")
	resetSelectedChordTypes()
	resetChordInversionStates()
	updateScaleData()
	updateScaleDegreeHeaders()
	showScaleStatus()
end

----

local function scaleIsPentatonic()

	local scaleType = getScaleType()
	local scaleTypeName = string.lower(scales[scaleType].name)
	return string.match(scaleTypeName, "pentatonic")
end


function scaleChordAction(scaleNoteIndex)

	if scaleIsPentatonic() and scaleNoteIndex > 5 then
return
end

if scaleNoteIndex > #scaleNotes then
return
end

	setSelectedScaleNote(scaleNoteIndex)

	local selectedChordType = getSelectedChordType(scaleNoteIndex)
	local chord = scaleChords[scaleNoteIndex][selectedChordType]
	local actionDescription = "scale chord " .. scaleNoteIndex .. "  (" .. chord.code .. ")"

	playOrInsertScaleChord(actionDescription)
end

function previewScaleChordAction(scaleNoteIndex, velocity)

	if scaleIsPentatonic() and scaleNoteIndex > 5 then
return
end

if scaleNoteIndex > #scaleNotes then
return
end

	setSelectedScaleNote(scaleNoteIndex)
	previewScaleChord(velocity)
end

--

function scaleNoteAction(scaleNoteIndex)

	if scaleIsPentatonic() and scaleNoteIndex > 5 then
return
end

if scaleNoteIndex > #scaleNotes then
return
end

	setSelectedScaleNote(scaleNoteIndex)
	local actionDescription = "scale note " .. scaleNoteIndex
	playOrInsertScaleNote(0, actionDescription)
end

--

function lowerScaleNoteAction(scaleNoteIndex)

	if scaleIsPentatonic() and scaleNoteIndex > 5 then
return
end

if scaleNoteIndex > #scaleNotes then
return
end

  if getOctave() <= getOctaveMin() then
    return
  end

	setSelectedScaleNote(scaleNoteIndex)
	local actionDescription = "lower scale note " .. scaleNoteIndex
	playOrInsertScaleNote(-1, actionDescription)
end

--

function higherScaleNoteAction(scaleNoteIndex)

	if scaleIsPentatonic() and scaleNoteIndex > 5 then
return
end

if scaleNoteIndex > #scaleNotes then
return
end

  if getOctave() >= getOctaveMax() then
    return
  end

	setSelectedScaleNote(scaleNoteIndex)
	local actionDescription = "higher scale note " .. scaleNoteIndex
	playOrInsertScaleNote(1, actionDescription)
end


--

function previewScaleNoteAction(scaleNoteIndex)

	if scaleIsPentatonic() and scaleNoteIndex > 5 then
return
end

if scaleNoteIndex > #scaleNotes then
return
end

	setSelectedScaleNote(scaleNoteIndex)
	previewScaleNote(0)
end

function previewLowerScaleNoteAction(scaleNoteIndex)

	if scaleIsPentatonic() and scaleNoteIndex > 5 then
return
end

if scaleNoteIndex > #scaleNotes then
return
end

	if getOctave() <= getOctaveMin() then
		return
	end

	setSelectedScaleNote(scaleNoteIndex)
	previewScaleNote(-1)
end

function previewHigherScaleNoteAction(scaleNoteIndex)

	if scaleIsPentatonic() and scaleNoteIndex > 5 then
return
end

if scaleNoteIndex > #scaleNotes then
return
end

	if getOctave() >= getOctaveMax() then
		return
	end

	setSelectedScaleNote(scaleNoteIndex)
	previewScaleNote(1)
end

local function hex2rgb(arg) 

  local r, g, b = arg:match('(..)(..)(..)')
  r = tonumber(r, 16)/255
  g = tonumber(g, 16)/255
  b = tonumber(b, 16)/255
  return r, g, b
end

local function hexToNative(hex)
    local r, g, b = hex:match('(..)(..)(..)')
    r = tonumber(r, 16)
    g = tonumber(g, 16)
    b = tonumber(b, 16)
    return reaper.ColorToNative(r, g, b)
end

local function setColor(hexColor)

  local r, g, b = hex2rgb(hexColor)
  gfx.set(r, g, b, 1)
end

local themes = {
    dark = {
        background = "242424",
        buttonNormal = "333333",
        buttonHighlight = "474747",
        buttonPressed = "FFD700",
        buttonPressedText = "1A1A1A",
        chordSelected = "474747",
        chordSelectedHighlight = "717171",
        chordSelectedScaleNote = "DCDCDC",
        chordSelectedScaleNoteHighlight = "FFFFFF",
        chordOutOfScale = "181818",
        chordOutOfScaleHighlight = "474747",
        chordSuggestionStrong = "00FF00", -- Green
        chordSuggestionSafe = "00BFFF",   -- Deep Sky Blue
        chordSuggestionSpicy = "FF8C00",  -- Dark Orange
        buttonOutline = "1D1D1D",
        textNormal = "D7D7D7",
        textHighlight = "EEEEEE",
        textSelected = "F1F1F1",
        textSelectedHighlight = "FDFDFD",
        textSelectedScaleNote = "121212",
        textSelectedScaleNoteHighlight = "000000",
        headerOutline = "2E5C8A",
        headerBackground = "4A90D9",
        headerText = "E8F4FF",
        frameOutline = "0D0D0D",
        frameBackground = "181818",
        dropdownOutline = "090909",
        dropdownBackground = "1D1D1D",
        dropdownText = "D7D7D7",
        valueBoxOutline = "090909",
        valueBoxBackground = "161616",
        valueBoxText = "9F9F9F",
        generalText = "878787",
        
        -- Progression Slots
        slotBg = "262626",
        slotFilled = "3A6EA5",
        slotFilledText = "FFFFFF",
        slotSelectedText = "FFFFFF",
        slotFilledInfoText = "D0D0D0",
        slotSelectedInfoText = "FFFFFF",
        slotSelectedArrow = "FFFFFF",
        slotPlaying = "336699",
        slotSelected = "4D804D",
        slotHover = "333333",
        slotOutlineSelected = "80B380",
        slotOutline = "4D4D4D",
        slotLengthMarker = "FF9900",
        slotText = "FFFFFF",
        slotInfoText = "B3B3B3",
        slotEmptyText = "666666",
        slotArrow = "80B0D0",
        slotArrowHover = "FFFFFF",
        slotArrowBg = "2A4A6A",
        slotArrowBgHover = "3A5A7A",
        slotValueText = "C0D8E8",
        
        -- Tooltip
        tooltipBg = "1A1A1A",
        tooltipBorder = "FFD700",
        tooltipText = "FFFFFF",
        
        -- Header Buttons
        headerButtonBg = "404040",
        headerButtonBorder = "808080",
        headerButtonText = "FFFFFF",
        
        -- Linear View
        linearViewRoot = "FFD700",
        linearViewScale = "66B3FF",
        linearViewOutOfScale = "333333",
        linearViewTextInScale = "000000",
        linearViewTextOutOfScale = "808080",
        linearViewIntervalText = "CCCCCC",
        linearViewLegendTitle = "FFFFFF",
        linearViewLegendSub = "B3B3B3",
        
        -- Wheel View
        wheelBg = "262626",
        wheelPolygon = "808080",
        wheelPolygonActive = "FFFFFF",
        wheelTonic = "FFD700",
        wheelInScale = "80C0E6",
        wheelOutOfScale = "333333",
        wheelOutOfScaleFifths = "404040",
        wheelBorderActive = "FFFFFF",
        wheelBorderInactive = "666666",
        wheelHalo = "FFD700",
        wheelText = "000000",
        wheelRelativeMinor = "000000",
        wheelLegendTitle = "FFFFFF",
        wheelLegendSub = "B3B3B3",
        wheelLegendHalo = "FFD700",
        wheelLegendText = "FFFFFF",
        wheelFooterText = "B3B3B3",
        
        -- Piano
        pianoWhite = "FFFFFF",
        pianoWhiteActive = "FFD700",
        pianoWhiteText = "000000",
        pianoBlack = "000000",
        pianoBlackActive = "FFD700",
        pianoBlackText = "FFFFFF",
        pianoBlackTextActive = "000000",
        
        -- Chord Display
        chordDisplayBg = "1A1A1A",
        chordDisplayText = "FFFFFF",
        
        -- Bottom Buttons
        bottomButtonBg = "2D2D2D",
        bottomButtonText = "D7D7D7",
        
        -- Icons
        iconColor = "CCCCCC",
        
        -- Missing Keys (Dark)
        bottomButtonBgHover = "3D3D3D",
        topButtonTextHover = "FFD700",
        topButtonText = "D7D7D7",
        bottomButtonTextActive = "FFD700",
        pianoActive = "FFD700",
        pianoWhiteGrey = "CCCCCC",
        pianoTextActive = "000000",
        pianoTextExternal = "AAAAAA",
        pianoTextNormal = "000000",
        pianoBlackGrey = "333333",
        chordDisplayRecognized = "FFD700",
        chordDisplayRecognizedOutOfScale = "FF4444"
    },
    light = {
        background = "E0E0E0",
        buttonNormal = "C0C0C0",
        buttonHighlight = "B0B0B0",
        buttonPressed = "FFD700",
        buttonPressedText = "000000",
        chordSelected = "B0B0B0",
        chordSelectedHighlight = "A0A0A0",
        chordSelectedScaleNote = "404040",
        chordSelectedScaleNoteHighlight = "202020",
        chordOutOfScale = "F8F8F8",
        chordOutOfScaleHighlight = "E5E5E5",
        chordSuggestionStrong = "00AA00", -- Green
        chordSuggestionSafe = "0099CC",   -- Blue
        chordSuggestionSpicy = "FF8800",  -- Orange
        buttonOutline = "A0A0A0",
        textNormal = "202020",
        textHighlight = "000000",
        textSelected = "101010",
        textSelectedHighlight = "000000",
        textSelectedScaleNote = "FFFFFF",
        textSelectedScaleNoteHighlight = "FFFFFF",
        headerOutline = "2E5C8A",
        headerBackground = "4A90D9",
        headerText = "E8F4FF",
        frameOutline = "A0A0A0",
        frameBackground = "D0D0D0",
        dropdownOutline = "A0A0A0",
        dropdownBackground = "F0F0F0",
        dropdownText = "000000",
        valueBoxOutline = "A0A0A0",
        valueBoxBackground = "F0F0F0",
        valueBoxText = "000000",
        generalText = "202020",
        
        -- Progression Slots
        slotBg = "E0E0E0",
        slotFilled = "3A6EA5",
        slotFilledText = "FFFFFF",
        slotSelectedText = "FFFFFF",
        slotFilledInfoText = "D0E8FF",
        slotSelectedInfoText = "FFFFFF",
        slotSelectedArrow = "FFFFFF",
        slotPlaying = "6699CC",
        slotSelected = "80B380",
        slotHover = "D0D0D0",
        slotOutlineSelected = "4D804D",
        slotOutline = "A0A0A0",
        slotLengthMarker = "FF9900",
        slotText = "000000",
        slotInfoText = "404040",
        slotEmptyText = "808080",
        slotArrow = "FFFFFF",
        slotArrowHover = "000000",
        slotArrowBg = "B0D0F0",
        slotArrowBgHover = "90C0E0",
        slotValueText = "1A4A7A",
        
        -- Tooltip
        tooltipBg = "F0F0F0",
        tooltipBorder = "FFD700",
        tooltipText = "000000",
        
        -- Header Buttons
        headerButtonBg = "D0D0D0",
        headerButtonBorder = "A0A0A0",
        headerButtonText = "000000",
        
        -- Linear View
        linearViewRoot = "FFD700",
        linearViewScale = "66B3FF",
        linearViewOutOfScale = "E0E0E0",
        linearViewTextInScale = "000000",
        linearViewTextOutOfScale = "808080",
        linearViewIntervalText = "404040",
        linearViewLegendTitle = "000000",
        linearViewLegendSub = "404040",
        
        -- Wheel View
        wheelBg = "F0F0F0",
        wheelPolygon = "808080",
        wheelPolygonActive = "000000",
        wheelTonic = "FFD700",
        wheelInScale = "80C0E6",
        wheelOutOfScale = "E0E0E0",
        wheelOutOfScaleFifths = "D0D0D0",
        wheelBorderActive = "000000",
        wheelBorderInactive = "A0A0A0",
        wheelHalo = "FFD700",
        wheelText = "000000",
        wheelRelativeMinor = "000000",
        wheelLegendTitle = "000000",
        wheelLegendSub = "404040",
        wheelLegendHalo = "FFD700",
        wheelLegendText = "000000",
        wheelFooterText = "404040",
        
        -- Piano
        pianoWhite = "FFFFFF",
        pianoWhiteActive = "FFD700",
        pianoWhiteText = "000000",
        pianoBlack = "000000",
        pianoBlackActive = "FFD700",
        pianoBlackText = "909090",
        pianoBlackTextActive = "000000",
        
        -- Chord Display
        chordDisplayBg = "F0F0F0",
        chordDisplayText = "000000",
        
        -- Bottom Buttons
        bottomButtonBg = "B0B0B0",
        bottomButtonText = "000000",
        
        -- Icons
        iconColor = "404040",
        
        -- Missing Keys (Light)
        bottomButtonBgHover = "A0A0A0",
        topButtonTextHover = "0044AA",
        topButtonText = "202020",
        bottomButtonTextActive = "0044AA",
        pianoActive = "FFD700",
        pianoWhiteGrey = "E0E0E0",
        pianoTextActive = "000000",
        pianoTextExternal = "666666",
        pianoTextNormal = "000000",
        pianoBlackGrey = "404040",
        chordDisplayRecognized = "FFD700",
        chordDisplayRecognizedOutOfScale = "CC0000"
    },
    colorful = {
        background = "1A1A2E",
        buttonNormal = "16213E",
        buttonHighlight = "0F3460",
        buttonPressed = "E94560",
        buttonPressedText = "FFFFFF",
        chordSelected = "533483",
        chordSelectedHighlight = "7952B3",
        chordSelectedScaleNote = "00D9FF",
        chordSelectedScaleNoteHighlight = "00FFFF",
        chordOutOfScale = "0D0D1A",
        chordOutOfScaleHighlight = "1A1A2E",
        chordSuggestionStrong = "00FF88",
        chordSuggestionSafe = "00BFFF",
        chordSuggestionSpicy = "FF6B35",
        buttonOutline = "0F3460",
        textNormal = "EAEAEA",
        textHighlight = "FFFFFF",
        textSelected = "FFFFFF",
        textSelectedHighlight = "FFFFFF",
        textSelectedScaleNote = "1A1A2E",
        textSelectedScaleNoteHighlight = "000000",
        headerOutline = "E94560",
        headerBackground = "533483",
        headerText = "FFFFFF",
        frameOutline = "0F3460",
        frameBackground = "16213E",
        dropdownOutline = "533483",
        dropdownBackground = "1A1A2E",
        dropdownText = "EAEAEA",
        valueBoxOutline = "533483",
        valueBoxBackground = "16213E",
        valueBoxText = "00D9FF",
        generalText = "AAAACC",
        slotBg = "16213E",
        slotFilled = "533483",
        slotFilledText = "FFFFFF",
        slotSelectedText = "16213E",
        slotFilledInfoText = "00D9FF",
        slotSelectedInfoText = "16213E",
        slotSelectedArrow = "16213E",
        slotPlaying = "E94560",
        slotSelected = "00D9FF",
        slotHover = "0F3460",
        slotOutlineSelected = "00FFFF",
        slotOutline = "533483",
        slotLengthMarker = "FF6B35",
        slotText = "FFFFFF",
        slotInfoText = "AAAACC",
        slotEmptyText = "666699",
        slotArrow = "00D9FF",
        slotArrowHover = "FFFFFF",
        slotArrowBg = "533483",
        slotArrowBgHover = "7952B3",
        slotValueText = "00FFFF",
        tooltipBg = "16213E",
        tooltipBorder = "E94560",
        tooltipText = "FFFFFF",
        headerButtonBg = "533483",
        headerButtonBorder = "E94560",
        headerButtonText = "FFFFFF",
        linearViewRoot = "E94560",
        linearViewScale = "00D9FF",
        linearViewOutOfScale = "16213E",
        linearViewTextInScale = "FFFFFF",
        linearViewTextOutOfScale = "666699",
        linearViewIntervalText = "AAAACC",
        linearViewLegendTitle = "FFFFFF",
        linearViewLegendSub = "AAAACC",
        wheelBg = "1A1A2E",
        wheelPolygon = "533483",
        wheelPolygonActive = "E94560",
        wheelTonic = "E94560",
        wheelInScale = "00D9FF",
        wheelOutOfScale = "16213E",
        wheelOutOfScaleFifths = "0F3460",
        wheelBorderActive = "FFFFFF",
        wheelBorderInactive = "533483",
        wheelHalo = "E94560",
        wheelText = "FFFFFF",
        wheelRelativeMinor = "FFFFFF",
        wheelLegendTitle = "FFFFFF",
        wheelLegendSub = "AAAACC",
        wheelLegendHalo = "E94560",
        wheelLegendText = "FFFFFF",
        wheelFooterText = "AAAACC",
        pianoWhite = "EAEAEA",
        pianoWhiteActive = "E94560",
        pianoWhiteText = "1A1A2E",
        pianoBlack = "16213E",
        pianoBlackActive = "E94560",
        pianoBlackText = "00D9FF",
        pianoBlackTextActive = "FFFFFF",
        chordDisplayBg = "16213E",
        chordDisplayText = "FFFFFF",
        bottomButtonBg = "0F3460",
        bottomButtonText = "EAEAEA",
        iconColor = "00D9FF",
        bottomButtonBgHover = "533483",
        topButtonTextHover = "E94560",
        topButtonText = "EAEAEA",
        bottomButtonTextActive = "E94560",
        pianoActive = "E94560",
        pianoWhiteGrey = "CCCCDD",
        pianoTextActive = "FFFFFF",
        pianoTextExternal = "00D9FF",
        pianoTextNormal = "1A1A2E",
        pianoBlackGrey = "0F3460",
        chordDisplayRecognized = "E94560",
        chordDisplayRecognizedOutOfScale = "FF6B35"
    },
    neon = {
        background = "0A0A0F",
        buttonNormal = "151520",
        buttonHighlight = "252535",
        buttonPressed = "FF00FF",
        buttonPressedText = "000000",
        chordSelected = "1A1A2A",
        chordSelectedHighlight = "2A2A3A",
        chordSelectedScaleNote = "00FFFF",
        chordSelectedScaleNoteHighlight = "00FFFF",
        chordOutOfScale = "08080C",
        chordOutOfScaleHighlight = "151520",
        chordSuggestionStrong = "39FF14",
        chordSuggestionSafe = "00FFFF",
        chordSuggestionSpicy = "FF6600",
        buttonOutline = "252535",
        textNormal = "E0E0E0",
        textHighlight = "FFFFFF",
        textSelected = "FFFFFF",
        textSelectedHighlight = "FFFFFF",
        textSelectedScaleNote = "000000",
        textSelectedScaleNoteHighlight = "000000",
        headerOutline = "FF00FF",
        headerBackground = "9900FF",
        headerText = "FFFFFF",
        frameOutline = "252535",
        frameBackground = "151520",
        dropdownOutline = "9900FF",
        dropdownBackground = "0A0A0F",
        dropdownText = "E0E0E0",
        valueBoxOutline = "9900FF",
        valueBoxBackground = "151520",
        valueBoxText = "00FFFF",
        generalText = "9999BB",
        slotBg = "151520",
        slotFilled = "9900FF",
        slotFilledText = "FFFFFF",
        slotSelectedText = "151520",
        slotFilledInfoText = "00FFFF",
        slotSelectedInfoText = "151520",
        slotSelectedArrow = "151520",
        slotPlaying = "FF00FF",
        slotSelected = "00FFFF",
        slotHover = "252535",
        slotOutlineSelected = "00FFFF",
        slotOutline = "9900FF",
        slotLengthMarker = "39FF14",
        slotText = "FFFFFF",
        slotInfoText = "9999BB",
        slotEmptyText = "555577",
        slotArrow = "00FFFF",
        slotArrowHover = "FFFFFF",
        slotArrowBg = "9900FF",
        slotArrowBgHover = "CC00FF",
        slotValueText = "39FF14",
        tooltipBg = "151520",
        tooltipBorder = "FF00FF",
        tooltipText = "FFFFFF",
        headerButtonBg = "9900FF",
        headerButtonBorder = "FF00FF",
        headerButtonText = "FFFFFF",
        linearViewRoot = "FF00FF",
        linearViewScale = "00FFFF",
        linearViewOutOfScale = "151520",
        linearViewTextInScale = "FFFFFF",
        linearViewTextOutOfScale = "555577",
        linearViewIntervalText = "9999BB",
        linearViewLegendTitle = "FFFFFF",
        linearViewLegendSub = "9999BB",
        wheelBg = "0A0A0F",
        wheelPolygon = "9900FF",
        wheelPolygonActive = "FF00FF",
        wheelTonic = "FF00FF",
        wheelInScale = "00FFFF",
        wheelOutOfScale = "151520",
        wheelOutOfScaleFifths = "252535",
        wheelBorderActive = "FFFFFF",
        wheelBorderInactive = "9900FF",
        wheelHalo = "FF00FF",
        wheelText = "FFFFFF",
        wheelRelativeMinor = "FFFFFF",
        wheelLegendTitle = "FFFFFF",
        wheelLegendSub = "9999BB",
        wheelLegendHalo = "FF00FF",
        wheelLegendText = "FFFFFF",
        wheelFooterText = "9999BB",
        pianoWhite = "E0E0E0",
        pianoWhiteActive = "FF00FF",
        pianoWhiteText = "0A0A0F",
        pianoBlack = "151520",
        pianoBlackActive = "FF00FF",
        pianoBlackText = "00FFFF",
        pianoBlackTextActive = "FFFFFF",
        chordDisplayBg = "151520",
        chordDisplayText = "FFFFFF",
        bottomButtonBg = "252535",
        bottomButtonText = "E0E0E0",
        iconColor = "00FFFF",
        bottomButtonBgHover = "9900FF",
        topButtonTextHover = "FF00FF",
        topButtonText = "E0E0E0",
        bottomButtonTextActive = "FF00FF",
        pianoActive = "FF00FF",
        pianoWhiteGrey = "CCCCDD",
        pianoTextActive = "000000",
        pianoTextExternal = "00FFFF",
        pianoTextNormal = "0A0A0F",
        pianoBlackGrey = "252535",
        chordDisplayRecognized = "FF00FF",
        chordDisplayRecognizedOutOfScale = "FF6600"
    },
    ocean = {
        background = "0D1B2A",
        buttonNormal = "1B263B",
        buttonHighlight = "274060",
        buttonPressed = "00D4AA",
        buttonPressedText = "000000",
        chordSelected = "1B3A4B",
        chordSelectedHighlight = "2D5A6B",
        chordSelectedScaleNote = "48CAE4",
        chordSelectedScaleNoteHighlight = "90E0EF",
        chordOutOfScale = "091520",
        chordOutOfScaleHighlight = "1B263B",
        chordSuggestionStrong = "00D4AA",
        chordSuggestionSafe = "48CAE4",
        chordSuggestionSpicy = "FF7F50",
        buttonOutline = "274060",
        textNormal = "CAF0F8",
        textHighlight = "FFFFFF",
        textSelected = "FFFFFF",
        textSelectedHighlight = "FFFFFF",
        textSelectedScaleNote = "0D1B2A",
        textSelectedScaleNoteHighlight = "000000",
        headerOutline = "00D4AA",
        headerBackground = "0077B6",
        headerText = "FFFFFF",
        frameOutline = "274060",
        frameBackground = "1B263B",
        dropdownOutline = "0077B6",
        dropdownBackground = "0D1B2A",
        dropdownText = "CAF0F8",
        valueBoxOutline = "0077B6",
        valueBoxBackground = "1B263B",
        valueBoxText = "48CAE4",
        generalText = "90A4AE",
        slotBg = "1B263B",
        slotFilled = "0077B6",
        slotFilledText = "FFFFFF",
        slotSelectedText = "1B263B",
        slotFilledInfoText = "90E0EF",
        slotSelectedInfoText = "1B263B",
        slotSelectedArrow = "1B263B",
        slotPlaying = "00D4AA",
        slotSelected = "48CAE4",
        slotHover = "274060",
        slotOutlineSelected = "90E0EF",
        slotOutline = "0077B6",
        slotLengthMarker = "FF7F50",
        slotText = "FFFFFF",
        slotInfoText = "90A4AE",
        slotEmptyText = "546E7A",
        slotArrow = "48CAE4",
        slotArrowHover = "FFFFFF",
        slotArrowBg = "0077B6",
        slotArrowBgHover = "00A3CC",
        slotValueText = "90E0EF",
        tooltipBg = "1B263B",
        tooltipBorder = "00D4AA",
        tooltipText = "FFFFFF",
        headerButtonBg = "0077B6",
        headerButtonBorder = "00D4AA",
        headerButtonText = "FFFFFF",
        linearViewRoot = "00D4AA",
        linearViewScale = "48CAE4",
        linearViewOutOfScale = "1B263B",
        linearViewTextInScale = "FFFFFF",
        linearViewTextOutOfScale = "546E7A",
        linearViewIntervalText = "90A4AE",
        linearViewLegendTitle = "FFFFFF",
        linearViewLegendSub = "90A4AE",
        wheelBg = "0D1B2A",
        wheelPolygon = "0077B6",
        wheelPolygonActive = "00D4AA",
        wheelTonic = "00D4AA",
        wheelInScale = "48CAE4",
        wheelOutOfScale = "1B263B",
        wheelOutOfScaleFifths = "274060",
        wheelBorderActive = "FFFFFF",
        wheelBorderInactive = "0077B6",
        wheelHalo = "00D4AA",
        wheelText = "FFFFFF",
        wheelRelativeMinor = "FFFFFF",
        wheelLegendTitle = "FFFFFF",
        wheelLegendSub = "90A4AE",
        wheelLegendHalo = "00D4AA",
        wheelLegendText = "FFFFFF",
        wheelFooterText = "90A4AE",
        pianoWhite = "CAF0F8",
        pianoWhiteActive = "00D4AA",
        pianoWhiteText = "0D1B2A",
        pianoBlack = "1B263B",
        pianoBlackActive = "00D4AA",
        pianoBlackText = "48CAE4",
        pianoBlackTextActive = "FFFFFF",
        chordDisplayBg = "1B263B",
        chordDisplayText = "FFFFFF",
        bottomButtonBg = "274060",
        bottomButtonText = "CAF0F8",
        iconColor = "48CAE4",
        bottomButtonBgHover = "0077B6",
        topButtonTextHover = "00D4AA",
        topButtonText = "CAF0F8",
        bottomButtonTextActive = "00D4AA",
        pianoActive = "00D4AA",
        pianoWhiteGrey = "B0C4DE",
        pianoTextActive = "000000",
        pianoTextExternal = "48CAE4",
        pianoTextNormal = "0D1B2A",
        pianoBlackGrey = "274060",
        chordDisplayRecognized = "00D4AA",
        chordDisplayRecognizedOutOfScale = "FF7F50"
    },
    mono = {
        background = "1A1A1A",
        buttonNormal = "2A2A2A",
        buttonHighlight = "3A3A3A",
        buttonPressed = "FF3333",
        buttonPressedText = "FFFFFF",
        chordSelected = "3A3A3A",
        chordSelectedHighlight = "4A4A4A",
        chordSelectedScaleNote = "FFFFFF",
        chordSelectedScaleNoteHighlight = "FFFFFF",
        chordOutOfScale = "141414",
        chordOutOfScaleHighlight = "2A2A2A",
        chordSuggestionStrong = "FFFFFF",
        chordSuggestionSafe = "AAAAAA",
        chordSuggestionSpicy = "FF3333",
        buttonOutline = "3A3A3A",
        textNormal = "CCCCCC",
        textHighlight = "FFFFFF",
        textSelected = "FFFFFF",
        textSelectedHighlight = "FFFFFF",
        textSelectedScaleNote = "1A1A1A",
        textSelectedScaleNoteHighlight = "000000",
        headerOutline = "FF3333",
        headerBackground = "4A4A4A",
        headerText = "FFFFFF",
        frameOutline = "3A3A3A",
        frameBackground = "2A2A2A",
        dropdownOutline = "4A4A4A",
        dropdownBackground = "1A1A1A",
        dropdownText = "CCCCCC",
        valueBoxOutline = "4A4A4A",
        valueBoxBackground = "2A2A2A",
        valueBoxText = "FFFFFF",
        generalText = "888888",
        slotBg = "2A2A2A",
        slotFilled = "4A4A4A",
        slotFilledText = "FFFFFF",
        slotSelectedText = "2A2A2A",
        slotFilledInfoText = "CCCCCC",
        slotSelectedInfoText = "2A2A2A",
        slotSelectedArrow = "2A2A2A",
        slotPlaying = "FF3333",
        slotSelected = "FFFFFF",
        slotHover = "3A3A3A",
        slotOutlineSelected = "FFFFFF",
        slotOutline = "4A4A4A",
        slotLengthMarker = "FF3333",
        slotText = "FFFFFF",
        slotInfoText = "888888",
        slotEmptyText = "555555",
        slotArrow = "CCCCCC",
        slotArrowHover = "FFFFFF",
        slotArrowBg = "4A4A4A",
        slotArrowBgHover = "5A5A5A",
        slotValueText = "FFFFFF",
        tooltipBg = "2A2A2A",
        tooltipBorder = "FF3333",
        tooltipText = "FFFFFF",
        headerButtonBg = "4A4A4A",
        headerButtonBorder = "FF3333",
        headerButtonText = "FFFFFF",
        linearViewRoot = "FF3333",
        linearViewScale = "FFFFFF",
        linearViewOutOfScale = "2A2A2A",
        linearViewTextInScale = "1A1A1A",
        linearViewTextOutOfScale = "555555",
        linearViewIntervalText = "888888",
        linearViewLegendTitle = "FFFFFF",
        linearViewLegendSub = "888888",
        wheelBg = "1A1A1A",
        wheelPolygon = "4A4A4A",
        wheelPolygonActive = "FFFFFF",
        wheelTonic = "FF3333",
        wheelInScale = "FFFFFF",
        wheelOutOfScale = "2A2A2A",
        wheelOutOfScaleFifths = "3A3A3A",
        wheelBorderActive = "FFFFFF",
        wheelBorderInactive = "4A4A4A",
        wheelHalo = "FF3333",
        wheelText = "1A1A1A",
        wheelRelativeMinor = "1A1A1A",
        wheelLegendTitle = "FFFFFF",
        wheelLegendSub = "888888",
        wheelLegendHalo = "FF3333",
        wheelLegendText = "FFFFFF",
        wheelFooterText = "888888",
        pianoWhite = "E0E0E0",
        pianoWhiteActive = "FF3333",
        pianoWhiteText = "1A1A1A",
        pianoBlack = "2A2A2A",
        pianoBlackActive = "FF3333",
        pianoBlackText = "888888",
        pianoBlackTextActive = "FFFFFF",
        chordDisplayBg = "2A2A2A",
        chordDisplayText = "FFFFFF",
        bottomButtonBg = "3A3A3A",
        bottomButtonText = "CCCCCC",
        iconColor = "CCCCCC",
        bottomButtonBgHover = "4A4A4A",
        topButtonTextHover = "FF3333",
        topButtonText = "CCCCCC",
        bottomButtonTextActive = "FF3333",
        pianoActive = "FF3333",
        pianoWhiteGrey = "CCCCCC",
        pianoTextActive = "FFFFFF",
        pianoTextExternal = "888888",
        pianoTextNormal = "1A1A1A",
        pianoBlackGrey = "3A3A3A",
        chordDisplayRecognized = "FF3333",
        chordDisplayRecognizedOutOfScale = "FF6666"
    }
}

local function getThemeColor(key)
    if themeMode == 6 then return themes.mono[key]
    elseif themeMode == 5 then return themes.ocean[key]
    elseif themeMode == 4 then return themes.neon[key]
    elseif themeMode == 3 then return themes.colorful[key]
    elseif themeMode == 2 then return themes.light[key]
    else return themes.dark[key]
    end
end

setThemeColor = function(key)
    setColor(getThemeColor(key))
end

function drawDropdownIcon()
    local x = gfx.x
    local y = gfx.y
    
    setThemeColor("iconColor")
    
    local centerX = x + 7
    local topY = y + 8
    local halfWidth = 5
    local height = 5
    
    gfx.triangle(centerX - halfWidth, topY, centerX + halfWidth, topY, centerX, topY + height)
end

function drawLeftArrow()
    local x = gfx.x
    local y = gfx.y
    
    setThemeColor("iconColor")
    
    local width = 6
    local height = 10
    
    -- Triangle pointing left: (right, top), (right, bottom), (left, middle)
    gfx.triangle(x + width, y, x + width, y + height, x, y + height/2)
end

function drawRightArrow()
    local x = gfx.x
    local y = gfx.y
    
    setThemeColor("iconColor")
    
    local width = 6
    local height = 10
    
    -- Triangle pointing right: (left, top), (left, bottom), (right, middle)
    gfx.triangle(x, y, x, y + height, x + width, y + height/2)
end

--[[ window ]]--

function setDrawColorToBackground()
	setThemeColor("background")
end

--[[ buttons ]]--

function setDrawColorToNormalButton()
	setThemeColor("buttonNormal")
end

function setDrawColorToHighlightedButton()
	setThemeColor("buttonHighlight")
end

function setDrawColorToPressedButton()
	setThemeColor("buttonPressed")
end

function setDrawColorToPressedButtonText()
	setThemeColor("buttonPressedText")
end

--

function setDrawColorToSelectedChordTypeButton()
	setThemeColor("chordSelected")
end

function setDrawColorToHighlightedSelectedChordTypeButton()
	setThemeColor("chordSelectedHighlight")
end

--

function setDrawColorToSelectedChordTypeAndScaleNoteButton()
	setThemeColor("chordSelectedScaleNote")
end

function setDrawColorToHighlightedSelectedChordTypeAndScaleNoteButton()
	setThemeColor("chordSelectedScaleNoteHighlight")
end

--

function setDrawColorToOutOfScaleButton()
	setThemeColor("chordOutOfScale")
end

function setDrawColorToHighlightedOutOfScaleButton()
	setThemeColor("chordOutOfScaleHighlight")
end

--

function setDrawColorToButtonOutline()
	setThemeColor("buttonOutline")
end

--[[ button text ]]--

function setDrawColorToNormalButtonText()
	setThemeColor("textNormal")
end

function setDrawColorToHighlightedButtonText()
	setThemeColor("textHighlight")
end

--

function setDrawColorToSelectedChordTypeButtonText()
	setThemeColor("textSelected")
end

function setDrawColorToHighlightedSelectedChordTypeButtonText()
	setThemeColor("textSelectedHighlight")
end

--

function setDrawColorToSelectedChordTypeAndScaleNoteButtonText()
	setThemeColor("textSelectedScaleNote")
end

function setDrawColorToHighlightedSelectedChordTypeAndScaleNoteButtonText()
	setThemeColor("textSelectedScaleNoteHighlight")
end

--[[ buttons ]]--

function setDrawColorToHeaderOutline()
	setThemeColor("headerOutline")
end

function setDrawColorToHeaderBackground()
	setThemeColor("headerBackground")
end

function setDrawColorToHeaderText()
	setThemeColor("headerText")
end


--[[ frame ]]--
function setDrawColorToFrameOutline()
	setThemeColor("frameOutline")
end

function setDrawColorToFrameBackground()
	setThemeColor("frameBackground")
end


--[[ dropdown ]]--
function setDrawColorToDropdownOutline()
	setThemeColor("dropdownOutline")
end

function setDrawColorToDropdownBackground()
	setThemeColor("dropdownBackground")
end

function setDrawColorToDropdownText()
	setThemeColor("dropdownText")
end

--[[ valuebox ]]--
function setDrawColorToValueBoxOutline()
	setThemeColor("valueBoxOutline")
end

function setDrawColorToValueBoxBackground()
	setThemeColor("valueBoxBackground")
end

function setDrawColorToValueBoxText()
	setThemeColor("valueBoxText")
end


--[[ text ]]--
function setDrawColorToText()
	setThemeColor("generalText")
end


--[[ debug ]]--

function setDrawColorToRed()
	setColor("FF0000")
end





--[[
function setDrawColorToBackground()

	local r, g, b
	local backgroundColor = {36, 36, 36, 1}
	gfx.set(table.unpack(backgroundColor))
end

function setDrawColorToNormalButton()

	local backgroundColor = {45, 45, 45, 1}
	gfx.set(table.unpack(backgroundColor))
end

function setDrawColorToHighlightedButton()

	local backgroundColor = {71, 71, 71, 1}
	gfx.set(table.unpack(backgroundColor))
end

function setDrawColorToSelectedButton()

	local backgroundColor = {220, 220, 220, 1}
	gfx.set(table.unpack(backgroundColor))
end
]]--
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/TK Scripts/Midi/TK_ChordGun"

Docker = {}
Docker.__index = Docker

function Docker:new()

  local self = {}
  setmetatable(self, Docker)

  return self
end

local function dockWindow()

  local dockState = getDockState()
  gfx.dock(dockState)
  setWindowShouldBeDocked(true)

  guiShouldBeUpdated = true
end

function Docker:drawDockWindowContextMenu()

  setPositionAtMouseCursor()
  local selectedIndex = gfx.showmenu("dock window")

  if selectedIndex <= 0 then
    return
  end

  dockWindow()
  gfx.mouse_cap = 0
end

local function undockWindow()

  setWindowShouldBeDocked(false)
  gfx.dock(0)
  guiShouldBeUpdated = true
end

function Docker:drawUndockWindowContextMenu()

  setPositionAtMouseCursor()
  local selectedIndex = gfx.showmenu("undock window")

  if selectedIndex <= 0 then
    return
  end

  undockWindow()
  gfx.mouse_cap = 0
end

function Docker:update()

end

HitArea = {}
HitArea.__index = HitArea

function HitArea:new(x, y, width, height)
  local self = {}
  setmetatable(self, HitArea)

  self.x = x
  self.y = y
  self.width = width
  self.height = height

  return self
end
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/TK Scripts/Midi/TK_ChordGun"

OctaveValueBox = {}
OctaveValueBox.__index = OctaveValueBox

function OctaveValueBox:new(x, y, width, height)

  local self = {}
  setmetatable(self, OctaveValueBox)

  self.x = x
  self.y = y
  self.width = width
  self.height = height

  return self
end

function OctaveValueBox:drawRectangle()

    setDrawColorToValueBoxBackground()
    gfx.rect(self.x, self.y, self.width, self.height)
end

function OctaveValueBox:drawRectangleOutline()

    setDrawColorToValueBoxOutline()
    gfx.rect(self.x-1, self.y-1, self.width+1, self.height+1, false)
end

function OctaveValueBox:drawRectangles()

  self:drawRectangle()
  self:drawRectangleOutline() 
end

function OctaveValueBox:drawLeftArrow()

  gfx.x = self.x + 2
  gfx.y = self.y + 2
  drawLeftArrow()
end

function OctaveValueBox:drawRightArrow()

  local imageWidth = 6
  gfx.x = self.x + self.width - imageWidth - 3
  gfx.y = self.y + 2
  drawRightArrow()
end

function OctaveValueBox:drawImages()
  self:drawLeftArrow()
  self:drawRightArrow()
end

function OctaveValueBox:drawText()

  local octaveText = getOctave()

	setDrawColorToValueBoxText()
	local stringWidth, stringHeight = gfx.measurestr(octaveText)
	gfx.x = self.x + ((self.width - stringWidth) / 2)
	gfx.y = self.y + ((self.height - stringHeight) / 2)
	gfx.drawstr(octaveText)
end

local hitAreaWidth = s(18)

local function leftButtonHasBeenClicked(valueBox)
  local hitArea = HitArea:new(valueBox.x-s(1), valueBox.y-s(1), hitAreaWidth, valueBox.height+s(1))
  return mouseIsHoveringOver(hitArea) and leftMouseButtonIsHeldDown()
end

local function rightButtonHasBeenClicked(valueBox)
  local hitArea = HitArea:new(valueBox.x+valueBox.width-hitAreaWidth, valueBox.y-1, hitAreaWidth, valueBox.height+1)
  return mouseIsHoveringOver(hitArea) and leftMouseButtonIsHeldDown()
end

function OctaveValueBox:update()

  self:drawRectangles()
  self:drawImages()

  if mouseButtonIsNotPressedDown and leftButtonHasBeenClicked(self) then
    mouseButtonIsNotPressedDown = false
    decrementOctaveAction()
  end

  if mouseButtonIsNotPressedDown and rightButtonHasBeenClicked(self) then
    mouseButtonIsNotPressedDown = false
    incrementOctaveAction()
  end

  self:drawText()
end
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/TK Scripts/Midi/TK_ChordGun"

Label = {}
Label.__index = Label

function Label:new(x, y, width, height, getTextCallback, options)

  local self = {}
  setmetatable(self, Label)

  self.x = x
  self.y = y
  self.width = width
  self.height = height
  self.getTextCallback = getTextCallback
  self.xOffset = options and options.xOffset or 0
  self.align = options and options.align or "center"
  self.color = options and options.color
  self.fontId = options and options.fontId

  return self
end

function Label:drawRedOutline()
  setDrawColorToRed()
  gfx.rect(self.x, self.y, self.width, self.height, false)
end

function Label:drawText(text)

  if self.color then
    setColor(self.color)
  else
    setDrawColorToText()
  end
  
  if self.fontId then gfx.setfont(self.fontId) end
  
	local stringWidth, stringHeight = gfx.measurestr(text)
  local align = self.align or "center"
  if align == "left" then
    gfx.x = self.x + (self.xOffset or 0)
  elseif align == "right" then
    gfx.x = self.x + self.width - stringWidth + (self.xOffset or 0)
  else
    gfx.x = self.x + ((self.width - stringWidth) / 2) + (self.xOffset or 0)
  end
	gfx.y = self.y + ((self.height - stringHeight) / 2)
  gfx.drawstr(text)
  
  if self.fontId then gfx.setfont(1) end
end

function Label:update()
  --self:drawRedOutline()

  local text = self.getTextCallback()
  self:drawText(text)
end
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/TK Scripts/Midi/TK_ChordGun"

Header = {}
Header.__index = Header


local function getHeaderRadius()
	return s(5)
end

function Header:new(x, y, width, height, getTextCallback, scaleNoteIndex)

  local self = {}
  setmetatable(self, Header)

  self.x = x
  self.y = y
  self.width = width
  self.height = height
  self.getTextCallback = getTextCallback
  self.scaleNoteIndex = scaleNoteIndex

  return self
end

function Header:drawCorners(offset)
  local radius = getHeaderRadius()
  gfx.circle(self.x + radius + offset, self.y + radius + offset, radius, true)
  gfx.circle(self.x + self.width - radius - offset, self.y + radius + offset, radius, true)
end

function Header:drawEnds(offset)
  local radius = getHeaderRadius()
  gfx.rect(self.x + offset, self.y + radius + offset, radius, self.height - radius * 2 - 2 * offset, true)
  gfx.rect(self.x + self.width - radius - offset, self.y + radius + offset, radius + 1, self.height - radius * 2 - 2 * offset, true)
end

function Header:drawBodyAndSides(offset)
  local radius = getHeaderRadius()
  gfx.rect(self.x + radius + offset, self.y + offset, self.width - radius * 2 - 2 * offset, self.height - radius - 2 * offset, true)
end

function Header:drawHeaderOutline()

  setDrawColorToHeaderOutline()
  self:drawCorners(0)
  self:drawEnds(0)
  self:drawBodyAndSides(0)
end

function Header:drawRoundedRectangle()

  setDrawColorToHeaderBackground()
  self:drawCorners(1)
  self:drawEnds(1)
  self:drawBodyAndSides(1)
end

function Header:drawRoundedRectangles()
  
  self:drawHeaderOutline()
  self:drawRoundedRectangle()
end

function Header:drawText(text)

    setDrawColorToHeaderText()
    local stringWidth, stringHeight = gfx.measurestr(text)
    gfx.x = self.x + ((self.width + 4 * 1 - stringWidth) / 2)
    gfx.y = self.y + ((self.height - 4 * 1 - stringHeight) / 2)
    gfx.drawstr(text)
end

function Header:update()

    self:drawRoundedRectangles()

    local text = self.getTextCallback()
    self:drawText(text)
    
    if self.scaleNoteIndex and midiTriggerEnabled and midiTriggerMode == 2 then
      local triggerNote = getMidiTriggerNoteForColumn(self.scaleNoteIndex)
      if triggerNote then
        gfx.set(1, 0.85, 0.2, 1)
        local squareSize = 10
        gfx.rect(self.x + self.width - squareSize - 2, self.y + 2, squareSize, squareSize, 1)
      end
    end
    
    if self.scaleNoteIndex and mouseIsHoveringOver(self) then
      local rightClicked = (gfx.mouse_cap & 2 == 2)
      if mouseButtonIsNotPressedDown and rightClicked then
        mouseButtonIsNotPressedDown = false
        self:onRightClick()
      end
    end
end

function Header:onRightClick()
  if not self.scaleNoteIndex then return end
  
  local existingTrigger = getMidiTriggerNoteForColumn(self.scaleNoteIndex)
  local triggerLabel = existingTrigger and ("Clear Column Trigger (" .. getMidiNoteName(existingTrigger) .. ")") or "Assign Column Trigger..."
  
  local menu = triggerLabel
  
  gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
  local selection = gfx.showmenu(menu)
  
  if selection == 1 then
    if existingTrigger then
      clearMidiTriggerColumnMapping(self.scaleNoteIndex)
    else
      midiTriggerLearnTarget = {isColumn = true, columnIndex = self.scaleNoteIndex}
      reaper.ShowMessageBox("Press any MIDI key to assign it to column " .. self.scaleNoteIndex .. ".\n\nThe next incoming MIDI note will be mapped.", "MIDI Learn", 0)
    end
  end
end
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/TK Scripts/Midi/TK_ChordGun"

Frame = {}
Frame.__index = Frame


local function getFrameRadius()
	return s(10)
end

function Frame:new(x, y, width, height)

  local self = {}
  setmetatable(self, Frame)

  self.getX = type(x) == "function" and x or function() return x end
  self.getY = type(y) == "function" and y or function() return y end
  self.getWidth = type(width) == "function" and width or function() return width end
  self.getHeight = type(height) == "function" and height or function() return height end
  self.x = x
  self.y = y
  self.width = width
  self.height = height

  return self
end

function Frame:updateDimensions()
  if type(self.getWidth) == "function" then
    self.width = self.getWidth()
  end
  if type(self.getHeight) == "function" then
    self.height = self.getHeight()
  end
  if type(self.getX) == "function" then
    self.x = self.getX()
  end
  if type(self.getY) == "function" then
    self.y = self.getY()
  end
end

function Frame:drawCorners(offset)
  local radius = getFrameRadius()
  gfx.circle(self.x + radius + offset, self.y + radius + offset, radius, true)
  gfx.circle(self.x + self.width - radius - offset, self.y + radius + offset, radius, true)
  gfx.circle(self.x + radius + offset, self.y + self.height - radius - offset, radius, true)
  gfx.circle(self.x + self.width - radius - offset, self.y + self.height - radius - offset, radius, true)
end

function Frame:drawEnds(offset)
  local radius = getFrameRadius()
  gfx.rect(self.x + offset, self.y + radius + offset, radius, self.height - radius * 2, true)
  gfx.rect(self.x + self.width - radius - offset, self.y + radius - offset, radius + 1, self.height - radius * 2, true)
end

function Frame:drawBodyAndSides(offset)
  local radius = getFrameRadius()
  gfx.rect(self.x + radius + offset, self.y + offset, self.width - radius * 2 - 2 * offset, self.height + 1 - 2 * offset, true)
end

function Frame:drawFrameOutline()

  setDrawColorToFrameOutline()
  self:drawCorners(0)
  self:drawEnds(0)
  self:drawBodyAndSides(0)
end

function Frame:drawRectangle()

  setDrawColorToFrameBackground()
  self:drawCorners(1)
  self:drawEnds(1)
  self:drawBodyAndSides(1)
end

function Frame:drawRectangles()
  
  self:drawFrameOutline()
  self:drawRectangle()
end

function Frame:update()

    self:updateDimensions()
    self:drawRectangles()
end
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/TK Scripts/Midi/TK_ChordGun"

Dropdown = {}
Dropdown.__index = Dropdown

function Dropdown:new(x, y, width, height, options, defaultOptionIndex, onSelectionCallback)

  local self = {}
  setmetatable(self, Dropdown)

  self.x = x
  self.y = y
  self.width = width
  self.height = height
  self.options = options
  self.selectedIndex = defaultOptionIndex
  self.onSelectionCallback = onSelectionCallback
  self.dropdownList = {}
  self:updateDropdownList()
  return self
end

function Dropdown:drawRectangle()

		setDrawColorToDropdownBackground()
		gfx.rect(self.x, self.y, self.width, self.height)
end

function Dropdown:drawRectangleOutline()

		setDrawColorToDropdownOutline()
		gfx.rect(self.x-1, self.y-1, self.width+1, self.height+1, false)
end

function Dropdown:drawRectangles()

	self:drawRectangle()
	self:drawRectangleOutline()	
end

function Dropdown:drawText()

	local text = self.options[self.selectedIndex]

	setDrawColorToDropdownText()
	
	local availableWidth = self.width - 25 -- Left padding (7) + Icon width (14) + extra padding (4)
	local stringWidth, stringHeight = gfx.measurestr(text)
	
	if stringWidth > availableWidth then
		local ellipsis = "..."
		local ellipsisWidth = gfx.measurestr(ellipsis)
		
		while stringWidth + ellipsisWidth > availableWidth and #text > 0 do
			text = string.sub(text, 1, -2)
			stringWidth = gfx.measurestr(text)
		end
		text = text .. ellipsis
	end

	gfx.x = self.x + 7
	gfx.y = self.y + ((self.height - stringHeight) / 2)
	gfx.drawstr(text)
end

function Dropdown:drawImage()

	local imageWidth = 14
	gfx.x = self.x + self.width - imageWidth - 1
	gfx.y = self.y
	drawDropdownIcon()
end

local function dropdownHasBeenClicked(dropdown)
	return mouseIsHoveringOver(dropdown) and leftMouseButtonIsHeldDown()
end

function Dropdown:updateDropdownList()

	self.dropdownList = {}

	for index, option in pairs(self.options) do

		if (self.selectedIndex == index) then
			table.insert(self.dropdownList, "!" .. option)
		else
			table.insert(self.dropdownList, option)
		end
	end
end

function Dropdown:openMenu()

	setPositionAtMouseCursor()
	local selectedIndex = gfx.showmenu(table.concat(self.dropdownList,"|"))

	if selectedIndex <= 0 then
		return
	end

	self.selectedIndex = selectedIndex
	self.onSelectionCallback(selectedIndex)
	self:updateDropdownList()
end

function Dropdown:update()

		self:drawRectangles()
		self:drawText()
		self:drawImage()
		
		if mouseButtonIsNotPressedDown and dropdownHasBeenClicked(self) then
			mouseButtonIsNotPressedDown = false
			self:openMenu()
		end
end
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/TK Scripts/Midi/TK_ChordGun"

ChordInversionValueBox = {}
ChordInversionValueBox.__index = ChordInversionValueBox

function ChordInversionValueBox:new(x, y, width, height)

  local self = {}
  setmetatable(self, ChordInversionValueBox)

  self.x = x
  self.y = y
  self.width = width
  self.height = height

  return self
end

function ChordInversionValueBox:drawRectangle()

    setDrawColorToValueBoxBackground()
    gfx.rect(self.x, self.y, self.width, self.height)
end

function ChordInversionValueBox:drawRectangleOutline()

    setDrawColorToValueBoxOutline()
    gfx.rect(self.x-1, self.y-1, self.width+1, self.height+1, false)
end

function ChordInversionValueBox:drawRectangles()

  self:drawRectangle()
  self:drawRectangleOutline() 
end

function ChordInversionValueBox:drawLeftArrow()

  gfx.x = self.x + 2
  gfx.y = self.y + 2
  drawLeftArrow()
end

function ChordInversionValueBox:drawRightArrow()

  local imageWidth = 6
  gfx.x = self.x + self.width - imageWidth - 3
  gfx.y = self.y + 2
  drawRightArrow()
end

function ChordInversionValueBox:drawImages()
  self:drawLeftArrow()
  self:drawRightArrow()
end

function ChordInversionValueBox:drawText()

  local selectedScaleNote = getSelectedScaleNote()
  local chordInversionText = getChordInversionState(selectedScaleNote)

  if chordInversionText > -1 then
    chordInversionText = "0" .. chordInversionText
  end

	setDrawColorToValueBoxText()
	local stringWidth, stringHeight = gfx.measurestr(chordInversionText)
	gfx.x = self.x + ((self.width - stringWidth) / 2)
	gfx.y = self.y + ((self.height - stringHeight) / 2)
	gfx.drawstr(chordInversionText)
end

local hitAreaWidth = 18

local function leftButtonHasBeenClicked(valueBox)
  local hitArea = HitArea:new(valueBox.x-1, valueBox.y-1, hitAreaWidth, valueBox.height+1)
  return mouseIsHoveringOver(hitArea) and leftMouseButtonIsHeldDown()
end

local function rightButtonHasBeenClicked(valueBox)
  local hitArea = HitArea:new(valueBox.x+valueBox.width-hitAreaWidth, valueBox.y-1, hitAreaWidth, valueBox.height+1)
  return mouseIsHoveringOver(hitArea) and leftMouseButtonIsHeldDown()
end

local function shiftModifierIsHeldDown()
  return gfx.mouse_cap & 8 == 8
end

function ChordInversionValueBox:onLeftButtonPress()
  decrementChordInversion()
  previewScaleChord()
end

function ChordInversionValueBox:onLeftButtonShiftPress()
  decrementChordInversionAction()
end

function ChordInversionValueBox:onRightButtonPress()
  incrementChordInversion()
  previewScaleChord()
end

function ChordInversionValueBox:onRightButtonShiftPress()
  incrementChordInversionAction()
end

function ChordInversionValueBox:update()

  self:drawRectangles()
  self:drawImages()

  if mouseButtonIsNotPressedDown and leftButtonHasBeenClicked(self) then
    mouseButtonIsNotPressedDown = false

    if shiftModifierIsHeldDown() then
      self:onLeftButtonShiftPress()
    else
      self:onLeftButtonPress()
    end
  end

  if mouseButtonIsNotPressedDown and rightButtonHasBeenClicked(self) then
    mouseButtonIsNotPressedDown = false

    if shiftModifierIsHeldDown() then
      self:onRightButtonShiftPress()
    else
      self:onRightButtonPress()
    end
  end

  self:drawText()
end
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/TK Scripts/Midi/TK_ChordGun"

ChordButton = {}
ChordButton.__index = ChordButton



local currentlyHeldButton = nil

local holdModeEnabled = false

local lastPlayedChord = nil


local externalMidiNotes = {}
local lastProcessedMidiSignature = nil
local midiQueuePrimed = false
local internalNoteEvents = {}
local internalNoteTimeoutSeconds = 0.1 -- 100ms timeout

pruneInternalNoteEvents = function()
  if not reaper.time_precise then
    internalNoteEvents = {}
    return
  end

  local now = reaper.time_precise()
  for i = #internalNoteEvents, 1, -1 do
    if internalNoteEvents[i].expires <= now then
      table.remove(internalNoteEvents, i)
    end
  end
end

registerInternalNoteEvent = function(noteNumber, isNoteOn)
  if not reaper.time_precise then return end

  pruneInternalNoteEvents()
  internalNoteEvents[#internalNoteEvents + 1] = {
    note = noteNumber,
    isNoteOn = isNoteOn and true or false,
    expires = reaper.time_precise() + internalNoteTimeoutSeconds
  }
  suppressExternalMidiUntil = math.max(suppressExternalMidiUntil or 0, reaper.time_precise() + 0.1) -- 100ms global suppression
end

consumeInternalNoteEvent = function(noteNumber, isNoteOn)
  if not reaper.time_precise then return false end

  pruneInternalNoteEvents()
  for i = #internalNoteEvents, 1, -1 do
    local event = internalNoteEvents[i]
    if event.note == noteNumber and event.isNoteOn == (isNoteOn and true or false) then
      -- table.remove(internalNoteEvents, i) -- FIX: Keep event until expiration to prevent multi-trigger/feedback
      return true
    end
  end
  return false
end

local function buildMidiSignature(rawMessage, tsval, devIdx)
  return tostring(tsval or 0) .. ":" .. tostring(devIdx or -1) .. ":" .. (rawMessage or "")
end

isExternalDevice = function(devIdx)
  if devIdx == nil then
    return false
  end

  -- FIX: Ignore Virtual MIDI Keyboard (ID 63) to prevent feedback loops
  if devIdx == 63 then
      return false
  end

  if devIdx >= 0 then
    return true
  end

  return devIdx == -1
end

local function processExternalMidiInput()
  if not reaper.MIDI_GetRecentInputEvent then return end

  if suppressExternalMidiUntil and reaper.time_precise() < suppressExternalMidiUntil then
    return
  end

  pruneInternalNoteEvents()

  if not midiQueuePrimed then
    local retval, rawMessage, tsval, devIdx = reaper.MIDI_GetRecentInputEvent(0)
    if retval ~= 0 and rawMessage then
      lastProcessedMidiSignature = buildMidiSignature(rawMessage, tsval, devIdx)
    end
    midiQueuePrimed = true
    return
  end

  local firstSignature = nil
  local events = {}
  local index = 0
  while index < 512 do
    local retval, rawMessage, tsval, devIdx = reaper.MIDI_GetRecentInputEvent(index)
    if retval == 0 or not rawMessage or rawMessage == "" then
      break
    end
    local signature = buildMidiSignature(rawMessage, tsval, devIdx)
    if not firstSignature then firstSignature = signature end
    if signature == lastProcessedMidiSignature then
      break
    end
    events[#events + 1] = {
      rawMessage = rawMessage,
      tsval = tsval,
      devIdx = devIdx,
      signature = signature
    }
    index = index + 1
  end


  for i = #events, 1, -1 do
    local event = events[i]
    local rawMessage = event.rawMessage
    local status = rawMessage:byte(1) or 0
    local command = status & 0xF0
    local channel = status & 0x0F
    local msg2 = rawMessage:byte(2) or 0
    local msg3 = rawMessage:byte(3) or 0
    
    local isPhysicalInput = isExternalDevice(event.devIdx)

    local isNoteOn = (command == 0x90 and msg3 > 0)
    local isNoteOff = (command == 0x80) or (command == 0x90 and msg3 == 0)
    
    if isPhysicalInput and (isNoteOn or isNoteOff) then
      if consumeInternalNoteEvent(msg2, isNoteOn) then

      elseif isNoteOn then
        externalMidiNotes[msg2] = msg3 -- SLA VELOCITY OP IPV TRUE
      else
        externalMidiNotes[msg2] = nil
      end
    end
    ::continue::
  end

  if firstSignature then
    lastProcessedMidiSignature = firstSignature
  end
end

function ChordButton:new(text, x, y, width, height, scaleNoteIndex, chordTypeIndex, chordIsInScale)

  local self = {}
  setmetatable(self, ChordButton)

  self.text = text
  self.getX = type(x) == "function" and x or function() return x end
  self.getY = type(y) == "function" and y or function() return y end
  self.getWidth = type(width) == "function" and width or function() return width end
  self.getHeight = type(height) == "function" and height or function() return height end
  self.x = x
  self.y = y
  self.width = width
  self.height = height
  self.scaleNoteIndex = scaleNoteIndex
  self.chordTypeIndex = chordTypeIndex
  self.chordIsInScale = chordIsInScale

  return self
end

function ChordButton:updateDimensions()
  if type(self.getWidth) == "function" then
    self.width = self.getWidth()
  end
  if type(self.getHeight) == "function" then
    self.height = self.getHeight()
  end
  if type(self.getX) == "function" then
    self.x = self.getX()
  end
  if type(self.getY) == "function" then
    self.y = self.getY()
  end
end

function ChordButton:isSelectedChordType()

	local selectedScaleNote = getSelectedScaleNote()
	local selectedChordType = getSelectedChordType(self.scaleNoteIndex)

	local chordTypeIsSelected = (tonumber(self.chordTypeIndex) == tonumber(selectedChordType))
	local scaleNoteIsNotSelected = (tonumber(self.scaleNoteIndex) ~= tonumber(selectedScaleNote))

	return chordTypeIsSelected and scaleNoteIsNotSelected
end

function ChordButton:isSelectedChordTypeAndSelectedScaleNote()

	local selectedScaleNote = getSelectedScaleNote()
	local selectedChordType = getSelectedChordType(self.scaleNoteIndex)

	local chordTypeIsSelected = (tonumber(self.chordTypeIndex) == tonumber(selectedChordType))
	local scaleNoteIsSelected = (tonumber(self.scaleNoteIndex) == tonumber(selectedScaleNote))

	return chordTypeIsSelected and scaleNoteIsSelected
end


function ChordButton:drawButtonRectangle()


		if currentlyHeldButton == self then
			setDrawColorToPressedButton()
		elseif self:isSelectedChordTypeAndSelectedScaleNote() then

			if mouseIsHoveringOver(self) then
				setDrawColorToHighlightedSelectedChordTypeAndScaleNoteButton()
			else
				setDrawColorToSelectedChordTypeAndScaleNoteButton()
			end

		elseif self:isSelectedChordType() then

			if mouseIsHoveringOver(self) then
				setDrawColorToHighlightedSelectedChordTypeButton()
			else
				setDrawColorToSelectedChordTypeButton()
			end

		else

			if mouseIsHoveringOver(self) then
				setDrawColorToHighlightedButton()
			else

				if self.chordIsInScale then
					setDrawColorToNormalButton()
				else
					setDrawColorToOutOfScaleButton()
				end			
			end
		end

		gfx.rect(self.x, self.y, self.width, self.height)
end

function ChordButton:drawButtonOutline()

    setDrawColorToButtonOutline()
    gfx.rect(self.x-1, self.y-1, self.width+1, self.height+1, false)
    
    local suggestionType = getSuggestionType(self.scaleNoteIndex)
    if showHarmonicCompass and suggestionType and self.chordIsInScale and #scaleNotes == 7 then
        local squareSize = 10
        if suggestionType == "strong" then
            setThemeColor("chordSuggestionStrong")
        elseif suggestionType == "safe" then
            setThemeColor("chordSuggestionSafe")
        elseif suggestionType == "spicy" then
            setThemeColor("chordSuggestionSpicy")
        end
        gfx.rect(self.x + self.width - squareSize - 2, self.y + self.height - squareSize - 2, squareSize, squareSize, 1)
    end
    
    if midiTriggerEnabled and midiTriggerMode == 1 then
        local triggerNote = getMidiTriggerNoteForChord(self.scaleNoteIndex, self.chordTypeIndex)
        if triggerNote then
            gfx.set(1, 0.85, 0.2, 1)
            local squareSize = 10
            gfx.rect(self.x + 2, self.y + 2, squareSize, squareSize, 1)
        end
    end
end

function ChordButton:drawRectangles()

	self:drawButtonRectangle()
	self:drawButtonOutline()	
end

function ChordButton:drawText()


	if currentlyHeldButton == self then
		setDrawColorToPressedButtonText()
	elseif self:isSelectedChordTypeAndSelectedScaleNote() then

		if mouseIsHoveringOver(self) then
			setDrawColorToHighlightedSelectedChordTypeAndScaleNoteButtonText()
		else
			setDrawColorToSelectedChordTypeAndScaleNoteButtonText()
		end

	elseif self:isSelectedChordType() then

		if mouseIsHoveringOver(self) then
			setDrawColorToHighlightedSelectedChordTypeButtonText()
		else
			setDrawColorToSelectedChordTypeButtonText()
		end

	else

		if mouseIsHoveringOver(self) then
			setDrawColorToHighlightedButtonText()
		else
			setDrawColorToNormalButtonText()
		end
	end

	local stringWidth, stringHeight = gfx.measurestr(self.text)
	gfx.x = self.x + ((self.width - stringWidth) / 2)
	gfx.y = self.y + ((self.height - stringHeight) / 2)
	gfx.drawstr(self.text)
end

local function buttonHasBeenClicked(button)
	return mouseIsHoveringOver(button) and leftMouseButtonIsHeldDown()
end

local function buttonHasBeenRightClicked(button)
	return mouseIsHoveringOver(button) and rightMouseButtonIsHeldDown()
end

local function shiftModifierIsHeldDown()
	return gfx.mouse_cap & 8 == 8
end

local function ctrlModifierIsHeldDown()
	return gfx.mouse_cap & 4 == 4
end

local function altModifierIsHeldDown()
	return gfx.mouse_cap & 16 == 16
end

function ChordButton:onPress()

	previewScaleChord()
end

function ChordButton:onShiftPress()

	local chord = scaleChords[self.scaleNoteIndex][self.chordTypeIndex]
	local actionDescription = "scale chord " .. self.scaleNoteIndex .. "  (" .. chord.code .. ")"
	playOrInsertScaleChord(actionDescription)
end

function ChordButton:onAltPress()


	local chord = scaleChords[self.scaleNoteIndex][self.chordTypeIndex]
	addChordToProgression(self.scaleNoteIndex, self.chordTypeIndex, self.text, selectedProgressionSlot, getOctave(), getChordInversionState(self.scaleNoteIndex))
	

	setSelectedScaleNote(self.scaleNoteIndex)
	setSelectedChordType(self.scaleNoteIndex, self.chordTypeIndex)
	
	local root = scaleNotes[self.scaleNoteIndex]
	local octave = getOctave()
	local notes = getChordNotesArray(root, chord, octave)
	
	playScaleChord(notes)
	setNotesThatArePlaying(notes)
	updateChordText(root, chord, notes)
end

function generateLeadingChords(targetScaleIndex, type, insertDirectly)
  local targetRoot = scaleNotes[targetScaleIndex]
  
  if type == 1 then
      local iiRoot = (targetRoot + 2) % 12
      local vRoot = (targetRoot + 7) % 12
      
      local iiScaleIndex = nil
      local vScaleIndex = nil
      
      for i, note in ipairs(scaleNotes) do
        if note % 12 == iiRoot then iiScaleIndex = i end
        if note % 12 == vRoot then vScaleIndex = i end
      end
      
      if iiScaleIndex and vScaleIndex then
         local iiChordIdx = 1
         for idx, chord in ipairs(scaleChords[iiScaleIndex]) do
            if chord.code == "min7" or chord.code == "m7" or chord.code == "min7b5" then iiChordIdx = idx break end
         end
         
         local vChordIdx = 1
         for idx, chord in ipairs(scaleChords[vScaleIndex]) do
            if chord.code == "7" or chord.code == "dom7" then vChordIdx = idx break end
         end
         
         local targetChordIdx = getSelectedChordType(targetScaleIndex)
         
         if insertDirectly then
            if not ensureActiveTake() then return end
            startUndoBlock()
            
            local iiRootNote = scaleNotes[iiScaleIndex]
            local iiChordData = scaleChords[iiScaleIndex][iiChordIdx]
            local iiNotes = getChordNotesArray(iiRootNote, iiChordData, getOctave())
            insertScaleChord(iiNotes, false)
            
            local vRootNote = scaleNotes[vScaleIndex]
            local vChordData = scaleChords[vScaleIndex][vChordIdx]
            local vNotes = getChordNotesArray(vRootNote, vChordData, getOctave())
            insertScaleChord(vNotes, false)
            
            local tRootNote = scaleNotes[targetScaleIndex]
            local tChordData = scaleChords[targetScaleIndex][targetChordIdx]
            local tNotes = getChordNotesArray(tRootNote, tChordData, getOctave())
            insertScaleChord(tNotes, false)
            
            endUndoBlock("Insert ii-V-I")
         else
            local iiText = getScaleNoteName(iiScaleIndex) .. scaleChords[iiScaleIndex][iiChordIdx]['display']
            addChordToProgression(iiScaleIndex, iiChordIdx, iiText, nil, getOctave(), 0)
            
            local vText = getScaleNoteName(vScaleIndex) .. scaleChords[vScaleIndex][vChordIdx]['display']
            addChordToProgression(vScaleIndex, vChordIdx, vText, nil, getOctave(), 0)
            
            local tText = getScaleNoteName(targetScaleIndex) .. scaleChords[targetScaleIndex][targetChordIdx]['display']
            addChordToProgression(targetScaleIndex, targetChordIdx, tText, nil, getOctave(), 0)
            
            guiShouldBeUpdated = true
         end
         return true
      else
         reaper.ShowMessageBox("Cannot generate Diatonic ii-V: Required roots (ii or V) not found in current scale.", "Theory Limit", 0)
         return false
      end

  elseif type == 2 then
      if not insertDirectly then
          reaper.ShowMessageBox("Tritone Substitutions often contain notes outside the scale.\n\nThey can only be inserted directly into MIDI, not saved to progression slots.", "Feature Limit", 0)
          return false
      end

      if not ensureActiveTake() then return end
      startUndoBlock()

      local iiRoot = (targetRoot + 2) % 12
      local iiNotes = {}
      local baseOctave = getOctave() + 1
      local r = iiRoot + (baseOctave * 12)
      iiNotes = {r, r+3, r+7, r+10}
      insertScaleChord(iiNotes, false)

      local subRoot = (targetRoot + 1) % 12
      r = subRoot + (baseOctave * 12)
      local subNotes = {r, r+4, r+7, r+10}
      insertScaleChord(subNotes, false)

      local targetChordIdx = getSelectedChordType(targetScaleIndex)
      local tRootNote = scaleNotes[targetScaleIndex]
      local tChordData = scaleChords[targetScaleIndex][targetChordIdx]
      local tNotes = getChordNotesArray(tRootNote, tChordData, getOctave())
      insertScaleChord(tNotes, false)

      endUndoBlock("Insert Tritone Sub (ii-bII-I)")
      return true
  end
end

function ChordButton:onRightClick()
    local checkCompass = showHarmonicCompass and "!" or ""
    local existingTrigger = getMidiTriggerNoteForChord(self.scaleNoteIndex, self.chordTypeIndex)
    local triggerLabel = existingTrigger and ("Clear MIDI Trigger (" .. getMidiNoteName(existingTrigger) .. ")") or "Assign MIDI Trigger..."
    
    local menu = "Add to Progression (Alt+Click)|Insert to MIDI (Shift+Click)|Preview (Click)|"
    menu = menu .. "|" .. triggerLabel .. "|"
    menu = menu .. "|>Generate Leading Chords|"
    menu = menu .. "Add Diatonic ii-V-I to Progression|"
    menu = menu .. "Insert Diatonic ii-V-I to MIDI|"
    menu = menu .. "Insert Tritone Sub (ii-bII-I) to MIDI|<|"
    menu = menu .. checkCompass .. "Show Harmonic Compass (Suggestions)"
    
    gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
    local selection = gfx.showmenu(menu)
    
    if selection == 1 then
        self:onAltPress()
    elseif selection == 2 then
        self:onShiftPress()
    elseif selection == 3 then
        self:onPress()
    elseif selection == 4 then
        if existingTrigger then
            clearMidiTriggerMapping(self.scaleNoteIndex, self.chordTypeIndex)
        else
            midiTriggerLearnTarget = {scaleNoteIndex = self.scaleNoteIndex, chordTypeIndex = self.chordTypeIndex}
            reaper.ShowMessageBox("Press any MIDI key to assign it to this chord.\n\nThe next incoming MIDI note will be mapped.", "MIDI Learn", 0)
        end
    elseif selection == 5 then
        generateLeadingChords(self.scaleNoteIndex, 1, false)
    elseif selection == 6 then
        generateLeadingChords(self.scaleNoteIndex, 1, true)
    elseif selection == 7 then
        generateLeadingChords(self.scaleNoteIndex, 2, true)
    elseif selection == 8 then
        showHarmonicCompass = not showHarmonicCompass
        setPersistentValue(ConfigKeys.showHarmonicCompass, tostring(showHarmonicCompass))
    end
end

function ChordButton:update()

	self:updateDimensions()
	self:drawRectangles()
	self:drawText()

	local isHovering = mouseIsHoveringOver(self)
	local leftButtonDown = leftMouseButtonIsHeldDown()
	

	if mouseButtonIsNotPressedDown and isHovering and leftButtonDown then
		mouseButtonIsNotPressedDown = false
		currentlyHeldButton = self
		lastPlayedChord = self
		
		setSelectedScaleNote(self.scaleNoteIndex)
		setSelectedChordType(self.scaleNoteIndex, self.chordTypeIndex)

		if shiftModifierIsHeldDown() then
			self:onShiftPress()
		elseif altModifierIsHeldDown() then
			self:onAltPress()
		else
			self:onPress()
		end		
	end
	

	if currentlyHeldButton == self and not leftButtonDown then

		if not holdModeEnabled then
			stopAllNotesFromPlaying()
			lastPlayedChord = nil
		end

		currentlyHeldButton = nil
	end
	

	if mouseButtonIsNotPressedDown and buttonHasBeenRightClicked(self) then
		mouseButtonIsNotPressedDown = false
        self:onRightClick()
	end
	

	if tooltipsEnabled and isHovering then
		local tooltip = "Click: Preview | Shift+Click: Insert | Alt+Click: Add to slot"
		
		local triggerNote = getMidiTriggerNoteForChord(self.scaleNoteIndex, self.chordTypeIndex)
		if triggerNote then
		    tooltip = tooltip .. "\nMIDI Trigger: " .. getMidiNoteName(triggerNote)
		end
		
        if showHarmonicCompass and self.chordIsInScale and #scaleNotes == 7 then
            local suggestionType = getSuggestionType(self.scaleNoteIndex)
            if suggestionType then
                local suggestionText = ""
                if suggestionType == "strong" then
                    suggestionText = "Strong Resolution (Green)"
                elseif suggestionType == "safe" then
                    suggestionText = "Safe Step (Blue)"
                elseif suggestionType == "spicy" then
                    suggestionText = "Spicy/Deceptive (Orange)"
                end
                tooltip = tooltip .. "\nSuggestion: " .. suggestionText
            end
        end

		local currentScale = scales[getScaleType()]
		if currentScale.isCustom then
			local chord = scaleChords[self.scaleNoteIndex][self.chordTypeIndex]
			local stepIntervals, cumulativeIntervals = getChordIntervals(chord)
			if stepIntervals then
				tooltip = tooltip .. "\n" .. self.text .. " intervals: " .. stepIntervals .. " (steps) | " .. cumulativeIntervals .. " (from root)"
			end
		end
		
		queueTooltip(tooltip, gfx.mouse_x, gfx.mouse_y)
	end
end


SimpleButton = {}
SimpleButton.__index = SimpleButton

function SimpleButton:new(text, x, y, width, height, onClick, onRightClick, getTooltip, drawBorder, customColorFn, customTextColorFn)
	local self = {}
	setmetatable(self, SimpleButton)
	self.text = text
	self.getText = type(text) == "function" and text or function() return text end
	self.x = x
	self.y = y
	self.width = width
	self.height = height
	self.onClick = onClick
	self.onRightClick = onRightClick
	self.getTooltip = getTooltip
  self.drawBorder = drawBorder
  self.customColorFn = customColorFn
  self.customTextColorFn = customTextColorFn
	return self
end

function SimpleButton:draw()

  if self.drawBorder then
    local customColor = self.customColorFn and self.customColorFn()
    if customColor then
      setColor(customColor)
    else
      if mouseIsHoveringOver(self) then
        setThemeColor("bottomButtonBgHover")
      else
        setThemeColor("bottomButtonBg")
      end
    end
    gfx.rect(self.x, self.y, self.width, self.height, true)
    
    local customTextColor = self.customTextColorFn and self.customTextColorFn()
    if customTextColor then
        setColor(customTextColor)
    else
        setThemeColor("bottomButtonText")
    end
  else
    if mouseIsHoveringOver(self) then
      setThemeColor("topButtonTextHover")
    else
      setThemeColor("topButtonText")
    end
  end
  
  local displayText = type(self.getText) == "function" and self.getText() or self.text
  
  if displayText == "__ARROW_UP__" then
      local cx = self.x + self.width / 2
      local cy = self.y + self.height / 2
      local s = math.min(self.width, self.height) / 4
      gfx.triangle(cx, cy - s, cx - s, cy + s, cx + s, cy + s)
  elseif displayText == "__ARROW_DOWN__" then
      local cx = self.x + self.width / 2
      local cy = self.y + self.height / 2
      local s = math.min(self.width, self.height) / 4
      gfx.triangle(cx, cy + s, cx - s, cy - s, cx + s, cy - s)
  else
      local stringWidth, stringHeight = gfx.measurestr(displayText)
      gfx.x = self.x + ((self.width - stringWidth) / 2)
      gfx.y = self.y + ((self.height - stringHeight) / 2)
      gfx.drawstr(displayText)
  end
  
  if tooltipsEnabled and mouseIsHoveringOver(self) and self.getTooltip then
    local tooltip = self.getTooltip()
    if tooltip then
      queueTooltip(tooltip, gfx.mouse_x, gfx.mouse_y)
    end
  end
end

function SimpleButton:update()
	self:draw()
	
	if dropdownBlocksInput then return end
	
	if mouseButtonIsNotPressedDown and mouseIsHoveringOver(self) then

		if self.onRightClick and gfx.mouse_cap == 2 then
			mouseButtonIsNotPressedDown = false
			self.onRightClick()
		elseif leftMouseButtonIsHeldDown() then
			mouseButtonIsNotPressedDown = false
			if self.onClick then self.onClick() end
		end
	end
end


ToggleButton = {}
ToggleButton.__index = ToggleButton

function ToggleButton:new(text, x, y, width, height, getState, onToggle, onRightClick, getTooltip, drawBorder)
	local self = {}
	setmetatable(self, ToggleButton)
	self.text = text
	self.x = x
	self.y = y
	self.width = width
	self.height = height
	self.getState = getState
	self.onToggle = onToggle
	self.onRightClick = onRightClick
	self.getTooltip = getTooltip
  self.drawBorder = drawBorder
	return self
end

function ToggleButton:draw()

  if self.drawBorder then
    local isActive = self.getState()
    
    if mouseIsHoveringOver(self) then
      setThemeColor("bottomButtonBgHover")
    else
      setThemeColor("bottomButtonBg")
    end
    gfx.rect(self.x, self.y, self.width, self.height, true)
    
    if isActive then
      setThemeColor("bottomButtonTextActive")
    else
      setThemeColor("bottomButtonText")
    end
  else
    local isActive = self.getState()
    
    if isActive then
      setThemeColor("topButtonTextHover")
    elseif mouseIsHoveringOver(self) then
      setThemeColor("topButtonTextHover")
    else
      setThemeColor("topButtonText")
    end
  end
	
	local stringWidth, stringHeight = gfx.measurestr(self.text)
	gfx.x = self.x + ((self.width - stringWidth) / 2)
	gfx.y = self.y + ((self.height - stringHeight) / 2)
	gfx.drawstr(self.text)
	

	if tooltipsEnabled and mouseIsHoveringOver(self) and self.getTooltip then
		local tooltip = self.getTooltip()
		if tooltip then
			queueTooltip(tooltip, gfx.mouse_x, gfx.mouse_y)
		end
	end
end

function ToggleButton:update()
	self:draw()
	
	if dropdownBlocksInput then return end
	
	if mouseButtonIsNotPressedDown and mouseIsHoveringOver(self) then
    if leftMouseButtonIsHeldDown() then
      mouseButtonIsNotPressedDown = false
      

      if self.onRightClick and ctrlModifierIsHeldDown() then
        self.onRightClick()
      else

        self.onToggle()
      end
    elseif rightMouseButtonIsHeldDown() then
      mouseButtonIsNotPressedDown = false
      if self.onRightClick then
        self.onRightClick()
      end
    end
	end
end


CycleButton = {}
CycleButton.__index = CycleButton

function CycleButton:new(x, y, width, height, options, getCurrentIndex, onCycle, drawBorder)
	local self = {}
	setmetatable(self, CycleButton)
	self.x = x
	self.y = y
	self.width = width
	self.height = height
	self.options = options
	self.getCurrentIndex = getCurrentIndex
	self.onCycle = onCycle
	self.drawBorder = drawBorder
	return self
end

function CycleButton:draw()

  if self.drawBorder then
    if mouseIsHoveringOver(self) then
      setThemeColor("bottomButtonBgHover")
    else
      setThemeColor("bottomButtonBg")
    end
    gfx.rect(self.x, self.y, self.width, self.height, true)
    
    if self.getCurrentIndex() > 1 then
        setThemeColor("bottomButtonTextActive")
    else
        setThemeColor("bottomButtonText")
    end
  else
    if mouseIsHoveringOver(self) then
      setThemeColor("topButtonTextHover")
    else
      setThemeColor("topButtonText")
    end
  end

	local currentIndex = self.getCurrentIndex()
	local text = self.options[currentIndex] or "?"
	
	local stringWidth, stringHeight = gfx.measurestr(text)
	gfx.x = self.x + ((self.width - stringWidth) / 2)
	gfx.y = self.y + ((self.height - stringHeight) / 2)
	gfx.drawstr(text)
end

function CycleButton:update()
	self:draw()
	
	if dropdownBlocksInput then return end
	
	if mouseButtonIsNotPressedDown and mouseIsHoveringOver(self) and leftMouseButtonIsHeldDown() then
		mouseButtonIsNotPressedDown = false
		local currentIndex = self.getCurrentIndex()
		local nextIndex = (currentIndex % #self.options) + 1
		self.onCycle(nextIndex)
	end
end


local helpWindowOpen = false

function showHelpWindow()

	if helpWindowOpen then return end
	
	-- Calculate and save UI scale for Help window
	local dynamicBaseWidth = getDynamicBaseWidth()
	local scaleX = gfx.w / dynamicBaseWidth
	local scaleY = gfx.h / baseHeight
	local uiScale = (scaleX + scaleY) / 2
	reaper.SetExtState("TK_ChordGun_Help", "uiScale", tostring(uiScale), false)

	local scriptPath = debug.getinfo(1, "S").source:match("@?(.*)")
	local scriptDir = scriptPath:match("(.+)[/\\]")
	local helpScriptPath = scriptDir .. "/TK_ChordGun_Help.lua"
	

	reaper.SetExtState("TK_ChordGun_Help", "shouldOpen", "1", false)
	helpWindowOpen = true
	


	local cmdID = reaper.AddRemoveReaScript(true, 0, helpScriptPath, false)
	if cmdID and cmdID > 0 then
		reaper.Main_OnCommand(cmdID, 0)

	end
end


local fifthWheelWindow = nil
local fifthWheelWindowOpen = false
local lastSyncedTonic = nil
local lastSyncedScale = nil

function showFifthWheel()
	if fifthWheelWindowOpen then return end
	fifthWheelWindowOpen = true
	
	local scriptPath = debug.getinfo(1, "S").source:match("@?(.*)")
	local scriptDir = scriptPath:match("(.+)[/\\]")
	
	local scaleX = gfx.w / baseWidth
	local scaleY = gfx.h / baseHeight
	local uiScale = (scaleX + scaleY) / 2
	reaper.SetExtState("TK_ChordGun_FifthWheel", "uiScale", tostring(uiScale), false)
	
	local wheelScript = [[
	local notes = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
	local notesFlat = {"C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"}
	
	local orderFifths = {1, 8, 3, 10, 5, 12, 7, 2, 9, 4, 11, 6}
	local orderChromatic = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12}
	
	local useFlats = false
	local viewMode = 1
	
	local isLightMode = reaper.GetExtState("TK_ChordGun", "lightMode") == "1"

	local function hex2rgb(arg) 
		local r, g, b = arg:match('(..)(..)(..)')
		r = tonumber(r, 16)/255
		g = tonumber(g, 16)/255
		b = tonumber(b, 16)/255
		return r, g, b
	end

	local function setColor(hexColor)
		local r, g, b = hex2rgb(hexColor)
		gfx.set(r, g, b, 1)
	end

	local function getContrastColor(hexColor)
		local r, g, b = hex2rgb(hexColor)
		local luminance = (0.299 * r + 0.587 * g + 0.114 * b)
		return luminance > 0.5 and "FFFFFF" or "000000"
	end

	local themes = {
		dark = {
			background = "242424",
			buttonNormal = "2D2D2D",
			buttonHighlight = "474747",
			buttonPressed = "FFD700",
			buttonPressedText = "1A1A1A",
			chordSelected = "474747",
			chordSelectedHighlight = "717171",
			chordSelectedScaleNote = "DCDCDC",
			chordSelectedScaleNoteHighlight = "FFFFFF",
			chordOutOfScale = "121212",
			chordOutOfScaleHighlight = "474747",
			buttonOutline = "1D1D1D",
			textNormal = "D7D7D7",
			textHighlight = "EEEEEE",
			textSelected = "F1F1F1",
			textSelectedHighlight = "FDFDFD",
			textSelectedScaleNote = "121212",
			textSelectedScaleNoteHighlight = "000000",
			headerOutline = "2E5C8A",
			headerBackground = "4A90D9",
			headerText = "E8F4FF",
			frameOutline = "0D0D0D",
			frameBackground = "181818",
			dropdownOutline = "090909",
			dropdownBackground = "1D1D1D",
			dropdownText = "D7D7D7",
			valueBoxOutline = "090909",
			valueBoxBackground = "161616",
			valueBoxText = "9F9F9F",
			generalText = "878787",
			
			-- Progression Slots
			slotBg = "262626",
			slotPlaying = "336699",
			slotSelected = "4D804D",
			slotHover = "333333",
			slotOutlineSelected = "80B380",
			slotOutline = "4D4D4D",
			slotLengthMarker = "FF9900",
			slotText = "FFFFFF",
			slotInfoText = "B3B3B3",
			slotEmptyText = "666666",
			slotArrow = "80B0D0",
			slotArrowHover = "FFFFFF",
			slotArrowBg = "2A4A6A",
			slotArrowBgHover = "3A5A7A",
			slotValueText = "C0D8E8",
			
			-- Tooltip
			tooltipBg = "1A1A1A",
			tooltipBorder = "FFD700",
			tooltipText = "FFFFFF",
			
			-- Header Buttons
			headerButtonBg = "404040",
			headerButtonBorder = "808080",
			headerButtonText = "FFFFFF",
			
			-- Linear View
			linearViewRoot = "FFD700",
			linearViewScale = "66B3FF",
			linearViewOutOfScale = "333333",
			linearViewTextInScale = "000000",
			linearViewTextOutOfScale = "808080",
			linearViewIntervalText = "CCCCCC",
			linearViewLegendTitle = "FFFFFF",
			linearViewLegendSub = "B3B3B3",
			
			-- Wheel View
			wheelBg = "262626",
			wheelPolygon = "808080",
			wheelPolygonActive = "FFFFFF",
			wheelTonic = "FFD700",
			wheelInScale = "80C0E6",
			wheelOutOfScale = "333333",
			wheelOutOfScaleFifths = "404040",
			wheelBorderActive = "FFFFFF",
			wheelBorderInactive = "808080",
			wheelHalo = "FFD700",
			wheelText = "000000",
			wheelRelativeMinor = "000000",
			wheelLegendTitle = "FFFFFF",
			wheelLegendSub = "B3B3B3",
			wheelLegendHalo = "FFD700",
			wheelLegendText = "FFFFFF",
			wheelFooterText = "B3B3B3",
			
			-- Piano
			pianoWhite = "FFFFFF",
			pianoWhiteActive = "FFD700",
			pianoWhiteText = "000000",
			pianoBlack = "000000",
			pianoBlackActive = "FFD700",
			pianoBlackText = "FFFFFF",
			pianoBlackTextActive = "000000",
			
			-- Chord Display
			chordDisplayBg = "1A1A1A",
			chordDisplayText = "FFFFFF",
			
			-- Bottom Buttons
			bottomButtonBg = "2D2D2D",
			bottomButtonText = "D7D7D7",
			
			-- Icons
			iconColor = "CCCCCC",
			
			-- Missing Keys (Dark)
			bottomButtonBgHover = "3D3D3D",
			topButtonTextHover = "FFFFFF",
			topButtonText = "D7D7D7",
			bottomButtonTextActive = "FFFFFF",
			pianoActive = "FFD700",
			pianoWhiteGrey = "CCCCCC",
			pianoTextActive = "000000",
			pianoTextExternal = "AAAAAA",
			pianoTextNormal = "000000",
			pianoBlackGrey = "333333",
			chordDisplayRecognized = "FFD700",
			chordDisplayRecognizedOutOfScale = "FF4444"
		},
		light = {
			background = "E0E0E0",
			buttonNormal = "D0D0D0",
			buttonHighlight = "C0C0C0",
			buttonPressed = "FFD700",
			buttonPressedText = "000000",
			chordSelected = "B0B0B0",
			chordSelectedHighlight = "A0A0A0",
			chordSelectedScaleNote = "404040",
			chordSelectedScaleNoteHighlight = "202020",
			chordOutOfScale = "F5F5F5",
			chordOutOfScaleHighlight = "E5E5E5",
			buttonOutline = "A0A0A0",
			textNormal = "202020",
			textHighlight = "000000",
			textSelected = "101010",
			textSelectedHighlight = "000000",
			textSelectedScaleNote = "FFFFFF",
			textSelectedScaleNoteHighlight = "FFFFFF",
			headerOutline = "2E5C8A",
			headerBackground = "4A90D9",
			headerText = "E8F4FF",
			frameOutline = "A0A0A0",
			frameBackground = "D0D0D0",
			dropdownOutline = "A0A0A0",
			dropdownBackground = "F0F0F0",
			dropdownText = "000000",
			valueBoxOutline = "A0A0A0",
			valueBoxBackground = "F0F0F0",
			valueBoxText = "000000",
			generalText = "202020",
			
			-- Progression Slots
			slotBg = "E0E0E0",
			slotPlaying = "6699CC",
			slotSelected = "80B380",
			slotHover = "D0D0D0",
			slotOutlineSelected = "4D804D",
			slotOutline = "A0A0A0",
			slotLengthMarker = "FF9900",
			slotText = "000000",
			slotInfoText = "404040",
			slotEmptyText = "808080",
			slotArrow = "2A5A8A",
			slotArrowHover = "000000",
			slotArrowBg = "B0D0F0",
			slotArrowBgHover = "90C0E0",
			slotValueText = "1A4A7A",
			
			-- Tooltip
			tooltipBg = "F0F0F0",
			tooltipBorder = "FFD700",
			tooltipText = "000000",
			
			-- Header Buttons
			headerButtonBg = "D0D0D0",
			headerButtonBorder = "A0A0A0",
			headerButtonText = "000000",
			
			-- Linear View
			linearViewRoot = "FFD700",
			linearViewScale = "66B3FF",
			linearViewOutOfScale = "E0E0E0",
			linearViewTextInScale = "000000",
			linearViewTextOutOfScale = "808080",
			linearViewIntervalText = "404040",
			linearViewLegendTitle = "000000",
			linearViewLegendSub = "404040",
			
			-- Wheel View
			wheelBg = "F0F0F0",
			wheelPolygon = "808080",
			wheelPolygonActive = "000000",
			wheelTonic = "FFD700",
			wheelInScale = "80C0E6",
			wheelOutOfScale = "E0E0E0",
			wheelOutOfScaleFifths = "D0D0D0",
			wheelBorderActive = "000000",
			wheelBorderInactive = "A0A0A0",
			wheelHalo = "FFD700",
			wheelText = "000000",
			wheelRelativeMinor = "000000",
			wheelLegendTitle = "000000",
			wheelLegendSub = "404040",
			wheelLegendHalo = "FFD700",
			wheelLegendText = "000000",
			wheelFooterText = "404040",
			
			-- Piano
			pianoWhite = "FFFFFF",
			pianoWhiteActive = "FFD700",
			pianoWhiteText = "000000",
			pianoBlack = "000000",
			pianoBlackActive = "FFD700",
			pianoBlackText = "909090",
			pianoBlackTextActive = "000000",
			
			-- Chord Display
			chordDisplayBg = "F0F0F0",
			chordDisplayText = "000000",
			
			-- Bottom Buttons
			bottomButtonBg = "D0D0D0",
			bottomButtonText = "000000",
			
			-- Icons
			iconColor = "404040",
			
			-- Missing Keys (Light)
			bottomButtonBgHover = "C0C0C0",
			topButtonTextHover = "000000",
			topButtonText = "202020",
			bottomButtonTextActive = "000000",
			pianoActive = "FFD700",
			pianoWhiteGrey = "E0E0E0",
			pianoTextActive = "000000",
			pianoTextExternal = "666666",
			pianoTextNormal = "000000",
			pianoBlackGrey = "404040",
			chordDisplayRecognized = "FFD700",
			chordDisplayRecognizedOutOfScale = "CC0000"
		}
	}

	local function getThemeColor(key)
		if isLightMode then return themes.light[key] else return themes.dark[key] end
	end

	local function getThemeColorRGB(key)
		local hex = getThemeColor(key)
		local r, g, b = hex2rgb(hex)
		return {r, g, b}
	end

	local function setThemeColor(key)
		setColor(getThemeColor(key))
	end
	
	local uiScale = tonumber(reaper.GetExtState("TK_ChordGun_FifthWheel", "uiScale")) or 1.0
	
	local function s(size)
		return math.floor(size * uiScale + 0.5)
	end
		
	local baseW, baseH = 400, 400
	local windowW, windowH = s(baseW), s(baseH)
	local lastW, lastH = windowW, windowH
	local centerX, centerY = windowW/2, windowH/2
	local radius = s(140)
	local noteRadius = s(28)
	
	-- Get saved window position from ExtState
	local savedX = tonumber(reaper.GetExtState("TK_ChordGun_FifthWheel", "windowX")) or -1
	local savedY = tonumber(reaper.GetExtState("TK_ChordGun_FifthWheel", "windowY")) or -1
	
	gfx.init("Circle of Fifths / Modes", windowW, windowH, 0, savedX, savedY)
	gfx.setfont(1, "Arial", s(16), string.byte('b'))

	local function drawButtons()
		local toggleText = useFlats and "b" or "#"
		gfx.setfont(2, "Arial", s(16), string.byte('b'))
		local toggleW = gfx.measurestr(toggleText)
		local toggleX = s(10)
		local toggleY = s(10)
		local toggleH = s(24)
		local toggleButtonX = toggleX
		local toggleButtonY = toggleY
		local toggleButtonW = s(24)
		
		setThemeColor("headerButtonBg")
		gfx.rect(toggleButtonX, toggleButtonY, toggleButtonW, toggleH, 1)
		setThemeColor("headerButtonBorder")
		gfx.rect(toggleButtonX, toggleButtonY, toggleButtonW, toggleH, 0)
		setThemeColor("headerButtonText")
		gfx.x = toggleButtonX + (toggleButtonW - toggleW) / 2
		gfx.y = toggleButtonY + (toggleH - s(16)) / 2
		gfx.drawstr(toggleText)
		
		local viewText = "Fifths"
		if viewMode == 2 then viewText = "Chromatic" 
		elseif viewMode == 3 then viewText = "Linear" 
		elseif viewMode == 4 then viewText = "Score" 
		elseif viewMode == 5 then viewText = "Guitar" end
		
		local orderW = gfx.measurestr(viewText)
		local orderButtonW = orderW + s(20)
		local orderButtonX = windowW - orderButtonW - s(10)
		
		setThemeColor("headerButtonBg")
		gfx.rect(orderButtonX, toggleButtonY, orderButtonW, toggleH, 1)
		setThemeColor("headerButtonBorder")
		gfx.rect(orderButtonX, toggleButtonY, orderButtonW, toggleH, 0)
		setThemeColor("headerButtonText")
		gfx.x = orderButtonX + (orderButtonW - orderW) / 2
		gfx.y = toggleButtonY + (toggleH - s(16)) / 2
		gfx.drawstr(viewText)
		
		return toggleButtonX, toggleButtonY, toggleButtonW, toggleH, orderButtonX, orderButtonW
	end

	local function drawLinearView(currentTonic, scalePattern, displayNotes)
		local keyWidth = windowW / 14
		local keyHeight = s(120)
		local startY = centerY - (keyHeight / 2)
		local startX = (windowW - (keyWidth * 12)) / 2
		
		local intervals = {"R", "b2", "2", "b3", "3", "4", "b5", "5", "b6", "6", "b7", "7"}
		
		for i = 0, 11 do
			local noteIndex = ((currentTonic - 1 + i) % 12) + 1
			local x = startX + (i * keyWidth)
			local isInScale = scalePattern[noteIndex]
			
			if isInScale then
				if i == 0 then
					setThemeColor("linearViewRoot")
				else
					setThemeColor("linearViewScale")
				end
				gfx.rect(x, startY, keyWidth - s(2), keyHeight, 1)
			else
				setThemeColor("linearViewOutOfScale")
				gfx.rect(x, startY, keyWidth - s(2), keyHeight, 1)
			end
			
			gfx.setfont(1, "Arial", s(16), string.byte('b'))
			local name = displayNotes[noteIndex]
			local nw, nh = gfx.measurestr(name)
			
			if isInScale then
				setThemeColor("linearViewTextInScale")
			else
				setThemeColor("linearViewTextOutOfScale")
			end
			
			gfx.x = x + (keyWidth - s(2) - nw)/2
			gfx.y = startY + keyHeight - nh - s(10)
			gfx.drawstr(name)
			
			if isInScale then
				gfx.setfont(5, "Arial", s(12))
				local intName = intervals[i+1]
				local iw, ih = gfx.measurestr(intName)
				gfx.x = x + (keyWidth - s(2) - iw)/2
				gfx.y = startY + keyHeight + s(5)
				setThemeColor("linearViewIntervalText")
				gfx.drawstr(intName)
			end
			
			if gfx.mouse_cap & 1 == 1 and not mouseWasDown then
				if gfx.mouse_x >= x and gfx.mouse_x <= x + keyWidth - s(2) and
				   gfx.mouse_y >= startY and gfx.mouse_y <= startY + keyHeight then
					reaper.SetExtState("TK_ChordGun_FifthWheel", "selectedTonic", tostring(noteIndex), false)
					mouseWasDown = true
				end
			end
		end
		
		gfx.setfont(5, "Arial", s(13))
		local legendY = startY - s(40)
		setThemeColor("linearViewLegendTitle")
		local titleText = "Linear Interval View"
		local titleW = gfx.measurestr(titleText)
		gfx.x = centerX - titleW / 2
		gfx.y = legendY
		gfx.drawstr(titleText)
		
		setThemeColor("linearViewLegendSub")
		local subText = "Shows scale structure relative to Root"
		local subW = gfx.measurestr(subText)
		gfx.x = centerX - subW / 2
		gfx.y = legendY + s(18)
		gfx.drawstr(subText)
	end

	local function drawScoreView(currentTonic, scalePattern, useFlats)
		local staffWidth = windowW - s(40)
		local staffX = s(20)
		local staffY = centerY
		local lineSpacing = s(10)
		
		setThemeColor("wheelBorderInactive")
		for i = -2, 2 do
			local y = staffY + (i * lineSpacing)
			gfx.line(staffX, y, staffX + staffWidth, y)
		end
		
		gfx.setfont(3, "Times New Roman", s(40), string.byte('b'))
		setThemeColor("textNormal")
		gfx.x = staffX + s(10)
		gfx.y = staffY - s(25)
		gfx.drawstr("G")
		
		local activeNotes = {}
		for i = 0, 11 do
			local noteIndex = ((currentTonic - 1 + i) % 12) + 1
			if scalePattern[noteIndex] then
				local octave = 0
				if noteIndex < currentTonic then octave = 1 end
				table.insert(activeNotes, {index = noteIndex, octave = octave})
			end
		end
		
		local whiteKeyMapSharp = {0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6}
		local whiteKeyMapFlat  = {0, 1, 1, 2, 2, 3, 4, 4, 5, 5, 6, 6}
		
		local noteSpacing = (staffWidth - s(60)) / math.max(1, #activeNotes)
		local startNoteX = staffX + s(50)
		
		for i, noteData in ipairs(activeNotes) do
			local noteIdx = noteData.index
			local octave = noteData.octave
			local chromaticIdx = noteIdx - 1
			
			local stepIndex
			local accidental = ""
			
			if useFlats then
				stepIndex = whiteKeyMapFlat[noteIdx]
				local whiteKeys = {true, false, true, false, true, true, false, true, false, true, false, true}
				if not whiteKeys[noteIdx] then accidental = "b" end
			else
				stepIndex = whiteKeyMapSharp[noteIdx]
				local isWhite = (chromaticIdx == 0 or chromaticIdx == 2 or chromaticIdx == 4 or chromaticIdx == 5 or chromaticIdx == 7 or chromaticIdx == 9 or chromaticIdx == 11)
				if not isWhite then accidental = "#" end
			end
			
			local totalStep = stepIndex + (octave * 7)
			
			local bottomLineY = staffY + (2 * lineSpacing)
			local noteY = bottomLineY - ((totalStep - 2) * (lineSpacing / 2))
			local noteX = startNoteX + ((i-1) * noteSpacing)
			
			if totalStep == 0 then
				setThemeColor("wheelBorderInactive")
				gfx.line(noteX - s(8), noteY, noteX + s(8), noteY)
			elseif totalStep == 12 then
				 setThemeColor("wheelBorderInactive")
				 gfx.line(noteX - s(8), noteY, noteX + s(8), noteY)
			end
			
			if i == 1 then setThemeColor("wheelTonic") else setThemeColor("wheelInScale") end
			
			local r = s(5)
			gfx.circle(noteX, noteY, r, 1)
			
			setThemeColor("textNormal")
			if totalStep < 6 then
				gfx.line(noteX + r, noteY, noteX + r, noteY - s(25))
			else
				gfx.line(noteX - r, noteY, noteX - r, noteY + s(25))
			end
			
			if accidental ~= "" then
				gfx.setfont(1, "Arial", s(18), string.byte('b'))
				local accW, accH = gfx.measurestr(accidental)
				gfx.x = noteX - s(15)
				gfx.y = noteY - accH/2
				gfx.drawstr(accidental)
			end
			
			gfx.setfont(5, "Arial", s(12))
			local name = (useFlats and notesFlat or notes)[noteIdx]
			local nw, nh = gfx.measurestr(name)
			gfx.x = noteX - nw/2
			gfx.y = staffY + (3 * lineSpacing) + s(10)
			setThemeColor("textNormal")
			gfx.drawstr(name)
		end
		
		gfx.setfont(5, "Arial", s(13))
		local legendY = staffY - s(60)
		setThemeColor("wheelLegendTitle")
		local titleText = "Score View"
		local titleW = gfx.measurestr(titleText)
		gfx.x = centerX - titleW / 2
		gfx.y = legendY
		gfx.drawstr(titleText)
	end

  local function drawGuitarView(currentTonic, scalePattern, displayNotes)
    local fretboardX = s(40)
    local fretboardY = s(80)
    local fretboardW = windowW - s(60)
    local fretboardH = s(160)
    
    local numStrings = 6
    local numFrets = 12
    
    local stringSpacing = fretboardH / (numStrings - 1)
    local fretSpacing = fretboardW / (numFrets + 1) 
    
    setThemeColor("wheelBorderInactive")
    local markers = {3, 5, 7, 9, 12}
    for _, fret in ipairs(markers) do
      local x = fretboardX + (fret * fretSpacing) - (fretSpacing / 2)
      local y = fretboardY + (fretboardH / 2)
      local r = s(4)
      if fret == 12 then
        gfx.circle(x, y - s(15), r, 1)
        gfx.circle(x, y + s(15), r, 1)
      else
        gfx.circle(x, y, r, 1)
      end
    end

    setThemeColor("textNormal") 
    for i = 0, numFrets do
      local x = fretboardX + (i * fretSpacing)
      if i == 0 then
        gfx.rect(x - s(2), fretboardY, s(4), fretboardH, 1)
      else
        gfx.line(x, fretboardY, x, fretboardY + fretboardH)
      end
      
      if i > 0 then
        gfx.setfont(5, "Arial", s(10))
        local num = tostring(i)
        local nw, nh = gfx.measurestr(num)
        gfx.x = x - (fretSpacing/2) - (nw/2)
        gfx.y = fretboardY + fretboardH + s(5)
        gfx.drawstr(num)
      end
    end
    
    local tuning = {64, 59, 55, 50, 45, 40}
    
    for i = 1, numStrings do
      local y = fretboardY + ((i-1) * stringSpacing)
      setThemeColor("textNormal")
      gfx.line(fretboardX, y, fretboardX + (numFrets * fretSpacing), y)
      
      local openNoteVal = tuning[i]
      local openNoteIdx = (openNoteVal % 12) + 1
      local stringName = displayNotes[openNoteIdx]
      gfx.setfont(5, "Arial", s(12))
      local sw, sh = gfx.measurestr(stringName)
      gfx.x = fretboardX - s(25)
      gfx.y = y - sh/2
      gfx.drawstr(stringName)
      
      for fret = 0, numFrets do
        local noteVal = openNoteVal + fret
        local noteIndex = (noteVal % 12) + 1
        
        if scalePattern[noteIndex] then
          local cx = fretboardX + (fret * fretSpacing)
          if fret > 0 then cx = cx - (fretSpacing / 2) end
          
          local r = s(9)
          
          if noteIndex == currentTonic then
            setThemeColor("wheelTonic")
          else
            setThemeColor("wheelInScale")
          end
          
          gfx.circle(cx, y, r, 1)
          
          setThemeColor("textNormal")
          gfx.circle(cx, y, r, 0)
          
          local name = displayNotes[noteIndex]
          gfx.setfont(5, "Arial", s(10), string.byte('b'))
          local nw, nh = gfx.measurestr(name)
          
          if isLightMode then gfx.set(0,0,0,1) else gfx.set(0,0,0,1) end
          
          gfx.x = cx - nw/2
          gfx.y = y - nh/2
          gfx.drawstr(name)
        end
      end
    end
    
    gfx.setfont(5, "Arial", s(13))
    local legendY = fretboardY - s(40)
    setThemeColor("wheelLegendTitle")
    local titleText = "Guitar Fretboard (Standard Tuning)"
    local titleW = gfx.measurestr(titleText)
    gfx.x = centerX - titleW / 2
    gfx.y = legendY
    gfx.drawstr(titleText)
  end

  function drawWheel()
		local w, h = gfx.w, gfx.h
		if w ~= lastW or h ~= lastH then
			if w ~= lastW then h = w else w = h end
			local dock, x, y = gfx.dock(-1, 0, 0, 0, 0)
			gfx.init("", w, h, dock, x, y)
			lastW, lastH = w, h
		end
		
		windowW, windowH = gfx.w, gfx.h
		uiScale = windowW / baseW
		
		centerX, centerY = windowW/2, windowH/2
		radius = s(140)
		noteRadius = s(28)

		setThemeColor("wheelBg")
		gfx.rect(0, 0, windowW, windowH, 1)
		
		local toggleX, toggleY, toggleW, toggleH, orderX, orderW = drawButtons()
		
		local currentTonic = tonumber(reaper.GetExtState("TK_ChordGun_FifthWheel", "tonic")) or 1
		local isCustomScale = reaper.GetExtState("TK_ChordGun_FifthWheel", "isCustom") == "1"
		local scalePattern = {}
		for i = 1, 12 do
			scalePattern[i] = reaper.GetExtState("TK_ChordGun_FifthWheel", "scale" .. i) == "1"
		end
		local displayNotes = useFlats and notesFlat or notes

		if viewMode == 3 then
			drawLinearView(currentTonic, scalePattern, displayNotes)
		elseif viewMode == 4 then
			drawScoreView(currentTonic, scalePattern, useFlats)
		elseif viewMode == 5 then
			drawGuitarView(currentTonic, scalePattern, displayNotes)
		else
			local noteOrder = (viewMode == 2) and orderChromatic or orderFifths
			
			local symmetryPoints = {}
			if viewMode == 2 then
				local activeNotes = {}
				for i = 1, 12 do if scalePattern[i] then table.insert(activeNotes, i) end end
				if #activeNotes > 0 then
					for shift = 1, 11 do
						local matches = 0
						for _, noteIdx in ipairs(activeNotes) do
							local shiftedIdx = ((noteIdx - 1 + shift) % 12) + 1
							if scalePattern[shiftedIdx] then matches = matches + 1 end
						end
						if matches == #activeNotes then
							local symNoteIdx = ((currentTonic - 1 + shift) % 12) + 1
							symmetryPoints[symNoteIdx] = true
						end
					end
				end
			end

			local function getHarmonicDistanceColor(noteIndex, tonicIndex)
				local pos1, pos2
				for i = 1, 12 do
					if orderFifths[i] == noteIndex then pos1 = i end
					if orderFifths[i] == tonicIndex then pos2 = i end
				end
				local diff = pos1 - pos2
				local dist = math.min(math.abs(diff), 12 - math.abs(diff))
				if dist == 0 then return {1.0, 0.84, 0.0}
				elseif dist == 1 then return ((diff == 1) or (diff == -11)) and {0.4, 0.85, 0.4} or {0.9, 0.4, 0.8}
				elseif dist == 2 then return {0.5, 0.9, 0.9}
				elseif dist == 3 then return {1.0, 0.6, 0.2}
				elseif dist == 4 then return {0.85, 0.5, 0.35}
				else return {0.5, 0.3, 0.3} end
			end			

			setThemeColor("wheelPolygon")
			if viewMode == 2 then
				gfx.circle(centerX, centerY, radius, 0)
			else
				local activeIndices = {}
				for i = 1, 12 do
					local noteIndex = noteOrder[i]
					if scalePattern[noteIndex] then table.insert(activeIndices, i) end
				end
				if #activeIndices > 1 then
					setThemeColor("wheelPolygonActive")
					for i = 1, #activeIndices do
						local idx1 = activeIndices[i]
						local idx2 = activeIndices[(i % #activeIndices) + 1]
						local angle1 = (idx1 - 1) * (math.pi * 2 / 12) - (math.pi / 2)
						local angle2 = (idx2 - 1) * (math.pi * 2 / 12) - (math.pi / 2)
						gfx.line(centerX + math.cos(angle1) * radius, centerY + math.sin(angle1) * radius,
								 centerX + math.cos(angle2) * radius, centerY + math.sin(angle2) * radius, 1)
					end
				end
			end

			for i = 1, 12 do
				local angle = (i - 1) * (math.pi * 2 / 12) - (math.pi / 2)
				local noteIndex = noteOrder[i]
				local x = centerX + math.cos(angle) * radius
				local y = centerY + math.sin(angle) * radius
				
				local isCurrentTonic = (noteIndex == currentTonic)
				local isInScale = scalePattern[noteIndex]
				local isSymmetryPoint = symmetryPoints[noteIndex]
				
				local currentNoteRadius = noteRadius
				local drawText = true
				if viewMode == 2 and not isInScale then
					currentNoteRadius = s(5)
					drawText = false
				end
				
				local color
				if isCustomScale or viewMode == 2 then
					if isCurrentTonic then color = getThemeColorRGB("wheelTonic")
					elseif isInScale then color = getThemeColorRGB("wheelInScale")
					else color = getThemeColorRGB("wheelOutOfScale") end
				else
					if isCurrentTonic then color = getThemeColorRGB("wheelTonic")
					elseif isInScale then 
						color = getHarmonicDistanceColor(noteIndex, currentTonic)
						color[1] = math.min(1.0, color[1] * 1.2)
						color[2] = math.min(1.0, color[2] * 1.2)
						color[3] = math.min(1.0, color[3] * 1.2)
					else color = getThemeColorRGB("wheelOutOfScaleFifths") end
				end
				
				gfx.set(color[1], color[2], color[3], 1)
				gfx.circle(x, y, currentNoteRadius, 1)
				
				if isCurrentTonic or isInScale then
					setThemeColor("wheelBorderActive")
					gfx.circle(x, y, currentNoteRadius, 0)
					gfx.circle(x, y, currentNoteRadius-1, 0)
					if not (isCustomScale or viewMode == 2) then gfx.circle(x, y, currentNoteRadius-2, 0) end
				else
					setThemeColor("wheelBorderInactive")
					gfx.circle(x, y, currentNoteRadius, 0)
				end
				
				if isSymmetryPoint and not isCurrentTonic then
					setThemeColor("wheelHalo")
					for r=4, 7 do gfx.circle(x, y, currentNoteRadius + s(r), 0) end
				end
				
				if drawText then
					if not isLightMode and not isInScale then
						gfx.set(1, 1, 1, 1)
					else
						setThemeColor("wheelText")
					end
					gfx.setfont(1, "Arial", s(16), string.byte('b'))
					local noteName = displayNotes[noteIndex]
					local textW, textH = gfx.measurestr(noteName)
					gfx.x = x - textW / 2
					gfx.y = y - textH / 2
					if viewMode == 1 then gfx.y = y - textH / 2 - s(6) end
					gfx.drawstr(noteName)
					
					if viewMode == 1 then
						local minorNoteIndex = ((noteIndex + 8) % 12) + 1
						local minorName = displayNotes[minorNoteIndex] .. "m"
						gfx.setfont(4, "Arial", s(13))
						local minorW, minorH = gfx.measurestr(minorName)
						gfx.x = x - minorW / 2
						gfx.y = y - minorH / 2 + s(8)
						
						local hexColor = isLightMode and themes.light.wheelRelativeMinor or themes.dark.wheelRelativeMinor
						if not isLightMode and not isInScale then
							hexColor = "808080"
						end
						
						local contrastColor = getContrastColor(hexColor)
						if contrastColor == "000000" then
							gfx.set(0, 0, 0, 1)
						else
							gfx.set(1, 1, 1, 1)
						end
						
						gfx.drawstr(minorName)
					end
				end
				
				if gfx.mouse_cap & 1 == 1 and not mouseWasDown then
					local dist = math.sqrt((gfx.mouse_x - x)^2 + (gfx.mouse_y - y)^2)
					if dist < noteRadius then
						reaper.SetExtState("TK_ChordGun_FifthWheel", "selectedTonic", tostring(noteIndex), false)
						mouseWasDown = true
					end
				end
			end
			
			gfx.setfont(5, "Arial", s(13))
			local legendY = centerY - s(20)
			if viewMode == 2 then
				setThemeColor("wheelLegendTitle")
				local titleText = "Chromatic Order"
				local titleW = gfx.measurestr(titleText)
				gfx.x = centerX - titleW / 2; gfx.y = legendY; gfx.drawstr(titleText)
				setThemeColor("wheelLegendSub")
				local subText = "Visualizes symmetry"; local subW = gfx.measurestr(subText)
				gfx.x = centerX - subW / 2; gfx.y = legendY + s(18); gfx.drawstr(subText)
				setThemeColor("wheelLegendHalo")
				local haloText = "Halo: Equivalent Tonic"; local haloW = gfx.measurestr(haloText)
				gfx.x = centerX - haloW / 2; gfx.y = legendY + s(36); gfx.drawstr(haloText)
			else
				setThemeColor("wheelLegendTitle")
				local titleText = "Color Legend:"
				local titleW = gfx.measurestr(titleText)
				gfx.x = centerX - titleW / 2; gfx.y = legendY - s(60); gfx.drawstr(titleText)
				local startY = legendY - s(40); local lineHeight = s(18)
				local legendItems = isCustomScale and {
					{{1.0, 0.84, 0.0}, "Tonic (root note)"}, {{0.5, 0.75, 0.9}, "In scale"}, {{0.2, 0.2, 0.2}, "Out of scale"}
				} or {
					{{1.0, 0.84, 0.0}, "Tonic"}, {{0.4, 0.85, 0.4}, "+1 Fifth up"}, {{0.9, 0.4, 0.8}, "-1 Fifth down"},
					{{0.5, 0.9, 0.9}, "+2 Fifths up"}, {{1.0, 0.6, 0.2}, "+3 Fifths up"}, {{0.85, 0.5, 0.35}, "+4 Fifths up"},
					{{0.5, 0.3, 0.3}, "+5/6 Fifths (Tritone)"}
				}
				for i, item in ipairs(legendItems) do
					gfx.set(item[1][1], item[1][2], item[1][3], 1)
					local boxSize = s(12); local boxX = centerX - s(50)
					gfx.rect(boxX, startY, boxSize, boxSize, 1)
					setThemeColor("wheelLegendText")
					gfx.x = boxX + boxSize + s(6); gfx.y = startY
					gfx.drawstr(item[2])
					startY = startY + lineHeight
				end
			end
		end

		gfx.setfont(3, "Arial", s(18))
		setThemeColor("wheelFooterText")
		local instr = "Click a note to change tonic - ESC to close"
		local instrW = gfx.measurestr(instr)
		gfx.x = (windowW - instrW) / 2
		gfx.y = windowH - s(20)
		gfx.drawstr(instr)
		
		if gfx.mouse_cap & 1 == 1 and not mouseWasDown then
			local mx, my = gfx.mouse_x, gfx.mouse_y
			if mx >= toggleX and mx <= toggleX + toggleW and my >= toggleY and my <= toggleY + toggleH then
				useFlats = not useFlats
				mouseWasDown = true
			elseif mx >= orderX and mx <= orderX + orderW and my >= toggleY and my <= toggleY + toggleH then
				viewMode = (viewMode % 5) + 1
				mouseWasDown = true
			end
		end
	end
		function main()
		drawWheel()
		gfx.update()
		
	local forceClose = reaper.GetExtState("TK_ChordGun_FifthWheel", "forceClose")
	if forceClose == "1" then
		reaper.SetExtState("TK_ChordGun_FifthWheel", "forceClose", "0", false)
		reaper.SetExtState("TK_ChordGun_FifthWheel", "closed", "1", false)
		return
	end
	
	local char = gfx.getchar()
	if char == 27 or char == -1 then
		local dockState, posX, posY = gfx.dock(-1, 0, 0, 0, 0)
		reaper.SetExtState("TK_ChordGun_FifthWheel", "windowX", tostring(posX), true)
		reaper.SetExtState("TK_ChordGun_FifthWheel", "windowY", tostring(posY), true)
		reaper.SetExtState("TK_ChordGun_FifthWheel", "closed", "1", false)
		return
	end		
		if gfx.mouse_cap & 1 == 0 then
			mouseWasDown = false
		end
		
		reaper.defer(main)
	end
	
	local mouseWasDown = false
	main()
]]
	local tempScriptPath = scriptDir .. "/TK_ChordGun_FifthWheel_Temp.lua"
	local file = io.open(tempScriptPath, "w")
	if file then
		file:write(wheelScript)
		file:close()
		
		-- Initialize ExtState for the new window
		local currentTonic = getScaleTonicNote()
		local currentScale = scales[getScaleType()]
		local isCustomScale = currentScale.isCustom == true
		
		reaper.SetExtState("TK_ChordGun_FifthWheel", "tonic", tostring(currentTonic), false)
		reaper.SetExtState("TK_ChordGun_FifthWheel", "closed", "0", false)
		reaper.SetExtState("TK_ChordGun_FifthWheel", "selectedTonic", "0", false)
		reaper.SetExtState("TK_ChordGun_FifthWheel", "isCustom", isCustomScale and "1" or "0", false)
		
		for i = 1, 12 do
			local inScale = scalePattern and scalePattern[i] or false
			reaper.SetExtState("TK_ChordGun_FifthWheel", "scale" .. i, inScale and "1" or "0", false)
		end
		
		-- Run the temporary script
		local command = reaper.AddRemoveReaScript(true, 0, tempScriptPath, true)
		if command > 0 then
			reaper.Main_OnCommand(command, 0)
		end
	end
end

function checkFifthWheelUpdates()
	if not fifthWheelWindowOpen then return end
	

	local currentTonic = getScaleTonicNote()
	local currentScale = scales[getScaleType()]
	local isCustomScale = currentScale.isCustom == true
	local scaleHash = ""
	for i = 1, 12 do
		scaleHash = scaleHash .. (scalePattern and scalePattern[i] and "1" or "0")
	end
	

	if currentTonic ~= lastSyncedTonic or scaleHash ~= lastSyncedScale then
		reaper.SetExtState("TK_ChordGun_FifthWheel", "tonic", tostring(currentTonic), false)
		reaper.SetExtState("TK_ChordGun_FifthWheel", "isCustom", isCustomScale and "1" or "0", false)
		for i = 1, 12 do
			local inScale = scalePattern and scalePattern[i] or false
			reaper.SetExtState("TK_ChordGun_FifthWheel", "scale" .. i, inScale and "1" or "0", false)
		end
		lastSyncedTonic = currentTonic
		lastSyncedScale = scaleHash
	end
	

	local closed = reaper.GetExtState("TK_ChordGun_FifthWheel", "closed")
	if closed == "1" then
		fifthWheelWindowOpen = false
		reaper.SetExtState("TK_ChordGun_FifthWheel", "closed", "0", false)
		lastSyncedTonic = nil
		lastSyncedScale = nil
		return
	end
	

	local selectedTonic = tonumber(reaper.GetExtState("TK_ChordGun_FifthWheel", "selectedTonic"))
	if selectedTonic and selectedTonic > 0 then
		setScaleTonicNote(selectedTonic)
		setSelectedScaleNote(1)
		setChordText("")
		resetSelectedChordTypes()
		resetChordInversionStates()
		updateScaleData()
		updateScaleDegreeHeaders()
		

		local updatedScale = scales[getScaleType()]
		local updatedIsCustom = updatedScale.isCustom == true
		reaper.SetExtState("TK_ChordGun_FifthWheel", "isCustom", updatedIsCustom and "1" or "0", false)
		
		for i = 1, 12 do
			local inScale = scalePattern and scalePattern[i] or false
			reaper.SetExtState("TK_ChordGun_FifthWheel", "scale" .. i, inScale and "1" or "0", false)
		end
		reaper.SetExtState("TK_ChordGun_FifthWheel", "tonic", tostring(selectedTonic), false)
		reaper.SetExtState("TK_ChordGun_FifthWheel", "selectedTonic", "0", false)
	end
end


PianoKeyboard = {}
PianoKeyboard.__index = PianoKeyboard

function PianoKeyboard:new(x, y, width, height, startNote, numOctaves)
	local self = {}
	setmetatable(self, PianoKeyboard)
	self.getX = type(x) == "function" and x or function() return x end
	self.getY = type(y) == "function" and y or function() return y end
	self.getWidth = type(width) == "function" and width or function() return width end
	self.getHeight = type(height) == "function" and height or function() return height end
	self.x = x
	self.y = y
	self.width = width
	self.height = height
	self.numOctaves = numOctaves or 2
	self.blackKeyPattern = {1, 1, 0, 1, 1, 1, 0}
	self:updateDimensions()
	return self
end

function PianoKeyboard:updateDimensions()
	if type(self.getWidth) == "function" then
		self.width = self.getWidth()
	end
	if type(self.getHeight) == "function" then
		self.height = self.getHeight()
	end
	if type(self.getX) == "function" then
		self.x = self.getX()
	end
	if type(self.getY) == "function" then
		self.y = self.getY()
	end
	self.numWhiteKeys = self.numOctaves * 7
	self.whiteKeyWidth = self.width / self.numWhiteKeys
	self.blackKeyWidth = self.whiteKeyWidth * 0.6
	self.blackKeyHeight = self.height * 0.6
end

local currentlyHeldSlot = nil
local openSlotDropdown = nil
local slotDropdownData = nil

ProgressionSlots = {}
ProgressionSlots.__index = ProgressionSlots

function ProgressionSlots:new(x, y, width, height)
	local self = {}
	setmetatable(self, ProgressionSlots)
	self.x = x
	self.y = y
	self.width = width
	self.height = height
	return self
end

function handleSlotDropdownInput()
	dropdownBlocksInput = false
	if not openSlotDropdown or not chordProgression[openSlotDropdown] or not slotDropdownData then
		return
	end
	
	local i = openSlotDropdown
	local slotWidth = slotDropdownData.slotWidth
	local slotHeight = slotDropdownData.slotHeight
	local dropdownHeight = s(36)
	local blockMargin = s(25)
	
	local x = slotDropdownData.x + ((i - 1) * slotWidth) + ((i - 1) * s(2))
	local y = slotDropdownData.y
	local dropY = y + slotHeight + s(2)
	
	local isHoveringDropdown = gfx.mouse_x >= x and gfx.mouse_x <= x + slotWidth and
	                           gfx.mouse_y >= dropY and gfx.mouse_y <= dropY + dropdownHeight
	
	local isNearDropdown = gfx.mouse_x >= x - blockMargin and gfx.mouse_x <= x + slotWidth + blockMargin and
	                       gfx.mouse_y >= dropY - blockMargin and gfx.mouse_y <= dropY + dropdownHeight + blockMargin
	
	if isNearDropdown then
		dropdownBlocksInput = true
	end
	
	if not isHoveringDropdown then
		return
	end
	
	local beats = chordProgression[i].beats or 1
	local repeats = chordProgression[i].repeats or 1
	local octave = chordProgression[i].octave or getOctave()
	local inversion = chordProgression[i].inversion
	if not inversion then
		inversion = getChordInversionState(chordProgression[i].scaleNoteIndex)
	end
	
	local arrowH = s(12)
	local arrowSpacing = s(6)
	local totalH = arrowH + arrowSpacing + arrowH
	local startY = dropY + (dropdownHeight - totalH) / 2
	local innerPadding = s(8)
	local innerWidth = slotWidth - (innerPadding * 2)
	local colSpacing = s(4)
	local totalSpacing = colSpacing * 3
	local colW = (innerWidth - totalSpacing) / 4
	
	local controls = {
		{value = beats, min = 0.5, max = 8, values = {0.5, 1, 2, 4, 8}, key = "beats"},
		{value = repeats, min = 1, max = 4, key = "repeats"},
		{value = octave, min = -1, max = 8, key = "octave"},
		{value = inversion, min = 0, max = 4, key = "inversion"}
	}
	
	for c, ctrl in ipairs(controls) do
		local colX = x + innerPadding + (c - 1) * (colW + colSpacing)
		
		local upY = startY
		local downY = startY + arrowH + arrowSpacing
		
		local mouseInCol = gfx.mouse_x >= colX and gfx.mouse_x <= colX + colW
		local mouseOnUp = mouseInCol and gfx.mouse_y >= upY and gfx.mouse_y < upY + arrowH
		local mouseOnDown = mouseInCol and gfx.mouse_y >= downY and gfx.mouse_y < downY + arrowH
		
		if mouseButtonIsNotPressedDown and gfx.mouse_cap & 1 == 1 then
			if mouseOnUp then
				mouseButtonIsNotPressedDown = false
				local newVal
				if ctrl.values then
					local idx = 1
					for vi, v in ipairs(ctrl.values) do
						if v == ctrl.value then idx = vi break end
					end
					if idx < #ctrl.values then
						newVal = ctrl.values[idx + 1]
					end
				else
					if ctrl.value < ctrl.max then
						newVal = ctrl.value + 1
					end
				end
				if newVal then
					chordProgression[i][ctrl.key] = newVal
				end
			elseif mouseOnDown then
				mouseButtonIsNotPressedDown = false
				local newVal
				if ctrl.values then
					local idx = 1
					for vi, v in ipairs(ctrl.values) do
						if v == ctrl.value then idx = vi break end
					end
					if idx > 1 then
						newVal = ctrl.values[idx - 1]
					end
				else
					if ctrl.value > ctrl.min then
						newVal = ctrl.value - 1
					end
				end
				if newVal then
					chordProgression[i][ctrl.key] = newVal
				end
			end
		end
	end
	
	if isHoveringDropdown and mouseButtonIsNotPressedDown and gfx.mouse_cap & 1 == 1 then
		mouseButtonIsNotPressedDown = false
	end
end

function ProgressionSlots:update()
  if currentlyHeldSlot and (gfx.mouse_cap & 1 == 0) then
    stopAllNotesFromPlaying()
    currentlyHeldSlot = nil
  end

	local slotWidth = (self.width - s(14)) / 8
	local slotHeight = self.height
	
	local dropdownHandled = false
	
	slotDropdownData = {
		x = self.x,
		y = self.y,
		slotWidth = slotWidth,
		slotHeight = slotHeight
	}

	for i = 1, maxProgressionSlots do
		local x = self.x + ((i - 1) * slotWidth) + ((i - 1) * s(2))
		local y = self.y
		
		local isHovering = gfx.mouse_x >= x and gfx.mouse_x <= x + slotWidth and
		                   gfx.mouse_y >= y and gfx.mouse_y <= y + slotHeight
		
		if currentProgressionIndex == i and progressionPlaying then
			setThemeColor("slotPlaying")
		elseif selectedProgressionSlot == i then
			setThemeColor("slotSelected")
		elseif isHovering then
			setThemeColor("slotHover")
		elseif chordProgression[i] then
			setThemeColor("slotFilled")
		else
			setThemeColor("slotBg")
		end
		
		gfx.rect(x, y, slotWidth, slotHeight, 1)
		
		if selectedProgressionSlot == i then
			setThemeColor("slotOutlineSelected")
			gfx.rect(x, y, slotWidth, slotHeight, 0)
			gfx.rect(x+1, y+1, slotWidth-2, slotHeight-2, 0)
		else
			setThemeColor("slotOutline")
			gfx.rect(x, y, slotWidth, slotHeight, 0)
		end
		
		if i == progressionLength then
			setThemeColor("slotLengthMarker")
			gfx.rect(x + slotWidth - s(3), y, s(3), slotHeight, 1)
		end
		
		if chordProgression[i] then
			local isSelected = (selectedProgressionSlot == i)
			if isSelected then
				setThemeColor("slotSelectedText")
			else
				setThemeColor("slotFilledText")
			end
			gfx.setfont(1, "Arial", fontSize(13))
			local textW, textH = gfx.measurestr(chordProgression[i].text)
			gfx.x = x + (slotWidth - textW) / 2
			gfx.y = y + s(5)
			gfx.drawstr(chordProgression[i].text)
			
			local beats = chordProgression[i].beats or 1
			local repeats = chordProgression[i].repeats or 1
			local octave = chordProgression[i].octave or getOctave()
			local inversion = chordProgression[i].inversion
			if not inversion then
				inversion = getChordInversionState(chordProgression[i].scaleNoteIndex)
			end
			
			local colW = (slotWidth - s(6)) / 4
			local colSpacing = s(2)
			local infoY = y + slotHeight - s(14)
			
			if isSelected then
				setThemeColor("slotSelectedInfoText")
			else
				setThemeColor("slotFilledInfoText")
			end
			gfx.setfont(1, "Arial", fontSize(10))
			
			local infoItems = {
				beats .. "b",
				"x" .. repeats,
				"o" .. octave,
				"i" .. inversion
			}
			
			for c, txt in ipairs(infoItems) do
				local colX = x + s(1) + (c - 1) * colW + (c - 1) * colSpacing
				local txtW = gfx.measurestr(txt)
				gfx.x = colX + (colW - txtW) / 2
				gfx.y = infoY
				gfx.drawstr(txt)
			end
			
			local plusSize = s(20)
			local plusX = x + slotWidth - plusSize
			local plusY = y
			local hoveringPlus = gfx.mouse_x >= plusX and gfx.mouse_x <= plusX + plusSize and
			                     gfx.mouse_y >= plusY and gfx.mouse_y <= plusY + plusSize
			
			if hoveringPlus or openSlotDropdown == i then
				setThemeColor("slotArrowHover")
			elseif isSelected then
				setThemeColor("slotSelectedArrow")
			else
				setThemeColor("slotArrow")
			end
			gfx.setfont(1, "Arial", fontSize(18))
			local plusStr = "+"
			local plusW, plusH = gfx.measurestr(plusStr)
			gfx.x = plusX + (plusSize - plusW) / 2
			gfx.y = plusY + (plusSize - plusH) / 2
			gfx.drawstr(plusStr)
			
			if mouseButtonIsNotPressedDown and hoveringPlus and gfx.mouse_cap & 1 == 1 then
				if openSlotDropdown == i then
					openSlotDropdown = nil
				else
					openSlotDropdown = i
				end
				mouseButtonIsNotPressedDown = false
				dropdownHandled = true
			end
		else
			setThemeColor("slotEmptyText")
			gfx.setfont(1, "Arial", fontSize(12))
			local num = tostring(i)
			local textW, textH = gfx.measurestr(num)
			gfx.x = x + (slotWidth - textW) / 2
			gfx.y = y + (slotHeight - textH) / 2
			gfx.drawstr(num)
		end
		
		if not dropdownHandled then
			if mouseButtonIsNotPressedDown and isHovering and gfx.mouse_cap & 1 == 1 and shiftModifierIsHeldDown() then
				progressionLength = i
				mouseButtonIsNotPressedDown = false
			elseif mouseButtonIsNotPressedDown and chordProgression[i] and isHovering and gfx.mouse_cap & 1 == 1 and not altModifierIsHeldDown() and not shiftModifierIsHeldDown() and not ctrlModifierIsHeldDown() then
				selectedProgressionSlot = i
				playChordFromSlot(i)
				currentlyHeldSlot = i
				mouseButtonIsNotPressedDown = false
			elseif mouseButtonIsNotPressedDown and not chordProgression[i] and isHovering and gfx.mouse_cap & 1 == 1 and not altModifierIsHeldDown() and not shiftModifierIsHeldDown() and not ctrlModifierIsHeldDown() then
				if selectedProgressionSlot == i then
					selectedProgressionSlot = nil
				else
					selectedProgressionSlot = i
				end
				mouseButtonIsNotPressedDown = false
			end
		end
		
		if mouseButtonIsNotPressedDown and isHovering and gfx.mouse_cap & 2 == 2 then
			if shiftModifierIsHeldDown() and chordProgression[i] then
				removeChordFromProgression(i)
				mouseButtonIsNotPressedDown = false
			elseif not shiftModifierIsHeldDown() then
				selectedProgressionSlot = nil
				mouseButtonIsNotPressedDown = false
			end
		end
		
		if tooltipsEnabled and isHovering and openSlotDropdown ~= i then
			local tooltip
			if chordProgression[i] then
				tooltip = "Click: Preview | [+]: Edit settings | Shift+Click: Loop end | Right-Click: Deselect | Shift+Right-Click: Clear"
			else
				tooltip = "Click: Select slot | Shift+Click: Set loop endpoint | Right-Click: Deselect"
			end
			queueTooltip(tooltip, gfx.mouse_x, gfx.mouse_y)
		end
	end
end

function drawSlotSettingsDropdown()
	if not openSlotDropdown or not chordProgression[openSlotDropdown] or not slotDropdownData then
		return
	end
	
	local i = openSlotDropdown
	local slotWidth = slotDropdownData.slotWidth
	local slotHeight = slotDropdownData.slotHeight
	local dropdownHeight = s(36)
	
	local x = slotDropdownData.x + ((i - 1) * slotWidth) + ((i - 1) * s(2))
	local y = slotDropdownData.y
	local dropY = y + slotHeight + s(2)
	
	local beats = chordProgression[i].beats or 1
	local repeats = chordProgression[i].repeats or 1
	local octave = chordProgression[i].octave or getOctave()
	local inversion = chordProgression[i].inversion
	if not inversion then
		inversion = getChordInversionState(chordProgression[i].scaleNoteIndex)
	end
	
	setThemeColor("slotArrowBg")
	gfx.rect(x, dropY, slotWidth, dropdownHeight, 1)
	setThemeColor("slotOutline")
	gfx.rect(x, dropY, slotWidth, dropdownHeight, 0)
	
	local arrowH = s(12)
	local arrowSpacing = s(6)
	local totalH = arrowH + arrowSpacing + arrowH
	local startY = dropY + (dropdownHeight - totalH) / 2
	local innerPadding = s(8)
	local innerWidth = slotWidth - (innerPadding * 2)
	local colSpacing = s(4)
	local totalSpacing = colSpacing * 3
	local colW = (innerWidth - totalSpacing) / 4
	
	local controls = {
		{value = beats, min = 0.5, max = 8, values = {0.5, 1, 2, 4, 8}, key = "beats"},
		{value = repeats, min = 1, max = 4, key = "repeats"},
		{value = octave, min = -1, max = 8, key = "octave"},
		{value = inversion, min = 0, max = 4, key = "inversion"}
	}
	
	local isHoveringDropdown = gfx.mouse_x >= x and gfx.mouse_x <= x + slotWidth and
	                           gfx.mouse_y >= dropY and gfx.mouse_y <= dropY + dropdownHeight
	
	for c, ctrl in ipairs(controls) do
		local colX = x + innerPadding + (c - 1) * (colW + colSpacing)
		
		local upY = startY
		local downY = startY + arrowH + arrowSpacing
		
		local mouseInCol = gfx.mouse_x >= colX and gfx.mouse_x <= colX + colW
		local mouseOnUp = mouseInCol and gfx.mouse_y >= upY and gfx.mouse_y < upY + arrowH
		local mouseOnDown = mouseInCol and gfx.mouse_y >= downY and gfx.mouse_y < downY + arrowH
		
		if mouseOnUp then
			setThemeColor("slotArrowHover")
		else
			setThemeColor("slotArrow")
		end
		gfx.setfont(1, "Arial", fontSize(10))
		local upStr = "▲"
		local upW = gfx.measurestr(upStr)
		gfx.x = colX + (colW - upW) / 2
		gfx.y = upY
		gfx.drawstr(upStr)
		
		if mouseOnDown then
			setThemeColor("slotArrowHover")
		else
			setThemeColor("slotArrow")
		end
		local downStr = "▼"
		local downW = gfx.measurestr(downStr)
		gfx.x = colX + (colW - downW) / 2
		gfx.y = downY
		gfx.drawstr(downStr)
		
		if mouseButtonIsNotPressedDown and gfx.mouse_cap & 1 == 1 then
			if mouseOnUp then
				local newVal
				if ctrl.values then
					local idx = 1
					for vi, v in ipairs(ctrl.values) do
						if v == ctrl.value then idx = vi break end
					end
					if idx < #ctrl.values then
						newVal = ctrl.values[idx + 1]
					end
				else
					if ctrl.value < ctrl.max then
						newVal = ctrl.value + 1
					end
				end
				if newVal then
					chordProgression[i][ctrl.key] = newVal
					mouseButtonIsNotPressedDown = false
				end
			elseif mouseOnDown then
				local newVal
				if ctrl.values then
					local idx = 1
					for vi, v in ipairs(ctrl.values) do
						if v == ctrl.value then idx = vi break end
					end
					if idx > 1 then
						newVal = ctrl.values[idx - 1]
					end
				else
					if ctrl.value > ctrl.min then
						newVal = ctrl.value - 1
					end
				end
				if newVal then
					chordProgression[i][ctrl.key] = newVal
					mouseButtonIsNotPressedDown = false
				end
			end
		end
	end
	
	if mouseButtonIsNotPressedDown and gfx.mouse_cap & 1 == 1 and not isHoveringDropdown then
		local plusSize = s(12)
		local plusX = x + slotWidth - plusSize - s(2)
		local plusY = slotDropdownData.y + s(2)
		local hoveringPlus = gfx.mouse_x >= plusX and gfx.mouse_x <= plusX + plusSize and
		                     gfx.mouse_y >= plusY and gfx.mouse_y <= plusY + plusSize
		if not hoveringPlus then
			openSlotDropdown = nil
		end
	end
end

function PianoKeyboard:getStartNote()

	local currentOctave = getOctave()
	return (currentOctave * 12)
end

function PianoKeyboard:getNoteFromPosition(noteNumber)

	local startNote = self:getStartNote()
	local relativeNote = noteNumber - startNote
	if relativeNote < 0 or relativeNote >= (self.numOctaves * 12) then
		return nil
	end
	
	local octave = math.floor(relativeNote / 12)
	local noteInOctave = relativeNote % 12
	

	local whiteKeyMap = {0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6}
	local isBlack = {false, true, false, true, false, false, true, false, true, false, true, false}
	
	local whiteKeyIndex = whiteKeyMap[noteInOctave + 1] + (octave * 7)
	
	return {
		whiteKeyIndex = whiteKeyIndex,
		isBlack = isBlack[noteInOctave + 1],
		noteInOctave = noteInOctave
	}
end

function PianoKeyboard:getActiveNotes()

	local activeNotes = {}
	

	local activeButton = currentlyHeldButton or lastPlayedChord
	
	if activeButton then
		local selectedScaleNote = getSelectedScaleNote()
		local selectedChordType = getSelectedChordType(selectedScaleNote)
		
		if selectedScaleNote and selectedChordType then
			if scaleChords[selectedScaleNote] and scaleChords[selectedScaleNote][selectedChordType] then
				local root = scaleNotes[selectedScaleNote]
				local chord = scaleChords[selectedScaleNote][selectedChordType]
				local octave = getOctave()
				
				local inversionOverride = nil
				if voiceLeadingEnabled then
					inversionOverride = getBestVoiceLeadingInversion(root, chord, octave)
				end

				activeNotes = getChordNotesArray(root, chord, octave, inversionOverride)
			end
		end
	end
	
	return activeNotes
end

function PianoKeyboard:drawWhiteKey(index, isActive, noteNumber, isExternalActive, isCKey, octaveIndex)
	local x = self.x + (index * self.whiteKeyWidth)
	local y = self.y
	local w = self.whiteKeyWidth - s(1)
	local h = self.height
	
	local noteInChromatic = noteNumber % 12
	local noteForScale = noteInChromatic + 1
	local inScale = scalePattern[noteForScale] or false
	

  if isActive or isExternalActive then
    setThemeColor("pianoActive")
  elseif inScale then
		setThemeColor("pianoWhite")
	else
		setThemeColor("pianoWhiteGrey")
	end
	gfx.rect(x, y, w, h, true)
	

	setColor("000000")
	gfx.rect(x, y, w, h, false)
	

  local noteName = notes[noteForScale]
  

  if scaleFilterMode == 2 and (noteInChromatic == 0 or noteInChromatic == 2 or noteInChromatic == 4 or noteInChromatic == 5 or noteInChromatic == 7 or noteInChromatic == 9 or noteInChromatic == 11) then

    local whiteKeys = {0, 2, 4, 5, 7, 9, 11}
    local whiteKeyIndex = nil
    for i, wk in ipairs(whiteKeys) do
      if wk == noteInChromatic then
        whiteKeyIndex = i
        break
      end
    end
    
    if whiteKeyIndex and scalePattern then

      local scaleNotes = {}
      for i = 1, 12 do
        if scalePattern[i] then
          table.insert(scaleNotes, (i - 1) % 12)
        end
      end
      
      if #scaleNotes > 0 then
        local scaleIdx = ((whiteKeyIndex - 1) % #scaleNotes) + 1
        local mappedNote = scaleNotes[scaleIdx]
        local mappedNoteName = notes[mappedNote + 1]
        

        if mappedNote ~= noteInChromatic then
          noteName = noteName .. ">" .. mappedNoteName
        end
      end
    end
  end
  
  gfx.setfont(1, "Arial", fontSize(14))
	local stringWidth, stringHeight = gfx.measurestr(noteName)
	

  if isActive then
		setThemeColor("pianoTextActive")
  elseif isExternalActive then
    setThemeColor("pianoTextExternal")
	else
		setThemeColor("pianoTextNormal")
	end
	
	gfx.x = x + (w - stringWidth) / 2
	gfx.y = y + h - stringHeight - s(4)
  gfx.drawstr(noteName)


  if isCKey then
    local octaveLabel = tostring(math.floor(noteNumber / 12) - 1)
    gfx.setfont(1, "Arial", fontSize(14))
    if isActive then
      setThemeColor("pianoTextActive")
    elseif isExternalActive then
      setThemeColor("pianoTextExternal")
    else
      setThemeColor("pianoTextNormal")
    end
    gfx.x = x + (w - stringWidth) / 2 + stringWidth + s(4)
    gfx.y = y + h - stringHeight - s(4)
    gfx.drawstr(octaveLabel)
  end
	

  gfx.setfont(1, "Arial", fontSize(15))
end

function PianoKeyboard:drawBlackKey(whiteKeyIndex, noteInOctave, isActive, noteNumber, isExternalActive)
	local x = self.x + ((whiteKeyIndex + 1) * self.whiteKeyWidth) - (self.blackKeyWidth / 2)
	local y = self.y
	local w = self.blackKeyWidth
	local h = self.blackKeyHeight
	
	local noteInChromatic = noteNumber % 12
	local noteForScale = noteInChromatic + 1
	local inScale = scalePattern[noteForScale] or false
	

  if isActive or isExternalActive then
    setThemeColor("pianoActive")
  elseif inScale then
		setThemeColor("pianoBlack")
	else
		setThemeColor("pianoBlackGrey")
	end
	gfx.rect(x, y, w, h, true)
	

	setColor("000000")
	gfx.rect(x, y, w, h, false)
	

  local noteName = notes[noteForScale]
  gfx.setfont(1, "Arial", fontSize(12))
	local stringWidth, stringHeight = gfx.measurestr(noteName)
	

  if isActive then
		setThemeColor("pianoTextActive")
  elseif isExternalActive then
    setThemeColor("pianoTextExternal")
	else
		setThemeColor("pianoBlackText")
	end
	
	gfx.x = x + (w - stringWidth) / 2
	gfx.y = y + h - stringHeight - s(3)
	gfx.drawstr(noteName)
	

  gfx.setfont(1, "Arial", fontSize(15))
end

function PianoKeyboard:draw()

	local activeNotes = self:getActiveNotes()
	local activeNoteSet = {}
	for _, note in ipairs(activeNotes) do
		activeNoteSet[note] = true
	end
  local externalNoteSet = externalMidiNotes or {}
	
	local startNote = self:getStartNote()
	

	for i = 0, self.numWhiteKeys - 1 do
		local octave = math.floor(i / 7)
		local keyInOctave = i % 7
		local noteNumber = startNote + (octave * 12)
		

    local whiteKeyToNote = {0, 2, 4, 5, 7, 9, 11}
		noteNumber = noteNumber + whiteKeyToNote[keyInOctave + 1]
		
    local isActive = activeNoteSet[noteNumber] or false
    local isExternalActive = externalNoteSet[noteNumber] or false
      local isCKey = (whiteKeyToNote[keyInOctave + 1] == 0)
      self:drawWhiteKey(i, isActive, noteNumber, isExternalActive, isCKey, octave)
	end
	

	for i = 0, self.numWhiteKeys - 1 do
		local octave = math.floor(i / 7)
		local keyInOctave = i % 7
		
		if self.blackKeyPattern[keyInOctave + 1] == 1 then
			local startNote = self:getStartNote()
			local noteNumber = startNote + (octave * 12)
			local whiteKeyToNote = {0, 2, 4, 5, 7, 9, 11}
			noteNumber = noteNumber + whiteKeyToNote[keyInOctave + 1] + 1
			
      local isActive = activeNoteSet[noteNumber] or false
      local isExternalActive = externalNoteSet[noteNumber] or false
      self:drawBlackKey(i, keyInOctave, isActive, noteNumber, isExternalActive)
		end
	end
end

function PianoKeyboard:update()
	self:updateDimensions()
	self:draw()
	
	if gfx.mouse_wheel ~= 0 then
		if gfx.mouse_x >= self.x and gfx.mouse_x <= self.x + self.width and
		   gfx.mouse_y >= self.y and gfx.mouse_y <= self.y + self.height then
			local currentOctave = getOctave()
			if gfx.mouse_wheel > 0 then
				if currentOctave < getOctaveMax() then
					setOctave(currentOctave + 1)
				end
			else
				if currentOctave > getOctaveMin() then
					setOctave(currentOctave - 1)
				end
			end
			gfx.mouse_wheel = 0
		end
	end
end

inputCharacters = {}

inputCharacters["0"] = 48
inputCharacters["1"] = 49
inputCharacters["2"] = 50
inputCharacters["3"] = 51
inputCharacters["4"] = 52
inputCharacters["5"] = 53
inputCharacters["6"] = 54
inputCharacters["7"] = 55
inputCharacters["8"] = 56
inputCharacters["9"] = 57

inputCharacters["a"] = 97
inputCharacters["b"] = 98
inputCharacters["c"] = 99
inputCharacters["d"] = 100
inputCharacters["e"] = 101
inputCharacters["f"] = 102
inputCharacters["g"] = 103
inputCharacters["h"] = 104
inputCharacters["i"] = 105
inputCharacters["j"] = 106
inputCharacters["k"] = 107
inputCharacters["l"] = 108
inputCharacters["m"] = 109
inputCharacters["n"] = 110
inputCharacters["o"] = 111
inputCharacters["p"] = 112
inputCharacters["q"] = 113
inputCharacters["r"] = 114
inputCharacters["s"] = 115
inputCharacters["t"] = 116
inputCharacters["u"] = 117
inputCharacters["v"] = 118
inputCharacters["w"] = 119
inputCharacters["x"] = 120
inputCharacters["y"] = 121
inputCharacters["z"] = 122


inputCharacters["!"] = 33
inputCharacters["@"] = 64
inputCharacters["#"] = 35
inputCharacters["$"] = 36
inputCharacters["%"] = 37
inputCharacters["^"] = 94
inputCharacters["&"] = 38
inputCharacters["*"] = 42
inputCharacters["("] = 40

inputCharacters["A"] = 65
inputCharacters["B"] = 66
inputCharacters["C"] = 67
inputCharacters["D"] = 68
inputCharacters["E"] = 69
inputCharacters["F"] = 70
inputCharacters["G"] = 71
inputCharacters["H"] = 72
inputCharacters["I"] = 73
inputCharacters["J"] = 74
inputCharacters["K"] = 75
inputCharacters["L"] = 76
inputCharacters["M"] = 77
inputCharacters["N"] = 78
inputCharacters["O"] = 79
inputCharacters["P"] = 80
inputCharacters["Q"] = 81
inputCharacters["R"] = 82
inputCharacters["S"] = 83
inputCharacters["T"] = 84
inputCharacters["U"] = 85
inputCharacters["V"] = 86
inputCharacters["W"] = 87
inputCharacters["X"] = 88
inputCharacters["Y"] = 89
inputCharacters["Z"] = 90

inputCharacters[","] = 44
inputCharacters["."] = 46
inputCharacters["<"] = 60
inputCharacters[">"] = 62
inputCharacters[")"] = 41
inputCharacters[";"] = 59
inputCharacters["/"] = 47
inputCharacters[":"] = 58
inputCharacters["?"] = 63

inputCharacters["SPACE"] = 32
inputCharacters["ESC"] = 27

inputCharacters["LEFTARROW"] = 1818584692
inputCharacters["RIGHTARROW"] = 1919379572
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/TK Scripts/Midi/TK_ChordGun"


local function moveEditCursorLeftByGrid()
  local editor = activeMidiEditor()
  if editor then

	  local commandId = 40047
	  reaper.MIDIEditor_OnCommand(editor, commandId)
  else

    reaper.Main_OnCommand(40104, 0)
  end
end

local function moveEditCursorRightByGrid()
  local editor = activeMidiEditor()
  if editor then

	  local commandId = 40048
	  reaper.MIDIEditor_OnCommand(editor, commandId)
  else

    reaper.Main_OnCommand(40105, 0)
  end
end

function handleInput(interface)

	local operatingSystem = string.lower(reaper.GetOS())

	inputCharacter = gfx.getchar()
	
	if inputCharacter == inputCharacters["ESC"] then
		gfx.quit()
	end

	if inputCharacter == inputCharacters["LEFTARROW"] then
		moveEditCursorLeftByGrid()
	end

	if inputCharacter == inputCharacters["RIGHTARROW"] then
		moveEditCursorRightByGrid()
	end


	local function middleMouseButtonIsHeldDown()
		return gfx.mouse_cap & 64 == 64
	end

	if inputCharacter == inputCharacters["SPACE"] or middleMouseButtonIsHeldDown() then
		stopAllNotesFromPlaying()
	end

	if gfx.mouse_wheel ~= 0 then
		local keySelectionFrameHeight = interface.keySelectionFrameHeight or s(25)
		local yMargin = sy(8) + keySelectionFrameHeight + sy(6)
		local yPadding = sy(30)
		local headerHeight = sy(25)
		
		local chordAreaTop = yMargin + yPadding + headerHeight
		local buttonHeight = sy(38)
		local innerSpacing = sx(2)
		local chordAreaBottom = chordAreaTop + (maxVisibleRows * (buttonHeight + innerSpacing))

		if gfx.mouse_y >= chordAreaTop and gfx.mouse_y <= chordAreaBottom then
			local maxRows = 0
			if scaleChords then
				for _, chords in ipairs(scaleChords) do
					if #chords > maxRows then maxRows = #chords end
				end
			end

			if gfx.mouse_wheel > 0 then
				if chordListScrollOffset > 0 then 
					chordListScrollOffset = chordListScrollOffset - 1
					guiShouldBeUpdated = true 
				end
			elseif gfx.mouse_wheel < 0 then
				if chordListScrollOffset < maxRows - maxVisibleRows then
					chordListScrollOffset = chordListScrollOffset + 1
					guiShouldBeUpdated = true 
				end
			end
			
			gfx.mouse_wheel = 0
		end
	end

	--


	local numberKeys = {"1", "2", "3", "4", "5", "6", "7", "8", "9", "0"}
	for i = 1, math.min(#scaleNotes, 10) do
		if inputCharacter == inputCharacters[numberKeys[i]] then
			previewScaleChordAction(i)
		end
	end

	--


	local shiftNumberKeys = {"!", "@", "#", "$", "%", "^", "&", "*", "(", ")"}
	for i = 1, math.min(#scaleNotes, 10) do
		if inputCharacter == inputCharacters[shiftNumberKeys[i]] then
			scaleChordAction(i)
		end
	end

	--


	local qwertyKeys = {"q", "w", "e", "r", "t", "y", "u", "i", "o", "p"}
	for i = 1, math.min(#scaleNotes, 10) do
		if inputCharacter == inputCharacters[qwertyKeys[i]] then
			previewHigherScaleNoteAction(i)
		end
	end

	--


	local asdfKeys = {"a", "s", "d", "f", "g", "h", "j", "k", "l", ";"}
	for i = 1, math.min(#scaleNotes, 10) do
		if inputCharacter == inputCharacters[asdfKeys[i]] then
			previewScaleNoteAction(i)
		end
	end

	--


	local zxcvKeys = {"z", "x", "c", "v", "b", "n", "m", ",", ".", "/"}
	for i = 1, math.min(#scaleNotes, 10) do
		if inputCharacter == inputCharacters[zxcvKeys[i]] then
			previewLowerScaleNoteAction(i)
		end
	end



	--


	local QWERTYKeys = {"Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"}
	for i = 1, math.min(#scaleNotes, 10) do
		if inputCharacter == inputCharacters[QWERTYKeys[i]] then
			higherScaleNoteAction(i)
		end
	end

	--


	local ASDFKeys = {"A", "S", "D", "F", "G", "H", "J", "K", "L", ":"}
	for i = 1, math.min(#scaleNotes, 10) do
		if inputCharacter == inputCharacters[ASDFKeys[i]] then
			scaleNoteAction(i)
		end
	end

	--


	local ZXCVKeys = {"Z", "X", "C", "V", "B", "N", "M", "<", ">", "?"}
	for i = 1, math.min(#scaleNotes, 10) do
		if inputCharacter == inputCharacters[ZXCVKeys[i]] then
			lowerScaleNoteAction(i)
		end
	end

-----------------


	local function shiftKeyIsHeldDown()
		return gfx.mouse_cap & 8 == 8
	end

	local function controlKeyIsHeldDown()
		return gfx.mouse_cap & 32 == 32 
	end

	local function optionKeyIsHeldDown()
		return gfx.mouse_cap & 16 == 16
	end

	local function commandKeyIsHeldDown()
		return gfx.mouse_cap & 4 == 4
	end

	--

	local function shiftKeyIsNotHeldDown()
		return gfx.mouse_cap & 8 ~= 8
	end

	local function controlKeyIsNotHeldDown()
		return gfx.mouse_cap & 32 ~= 32
	end

	local function optionKeyIsNotHeldDown()
		return gfx.mouse_cap & 16 ~= 16
	end

	local function commandKeyIsNotHeldDown()
		return gfx.mouse_cap & 4 ~= 4
	end

	--

	local function controlModifierIsActive()
		return controlKeyIsHeldDown() and optionKeyIsNotHeldDown() and commandKeyIsNotHeldDown()
	end

	local function optionModifierIsActive()
		return optionKeyIsHeldDown() and controlKeyIsNotHeldDown() and commandKeyIsNotHeldDown()
	end

	local function commandModifierIsActive()
		return commandKeyIsHeldDown() and optionKeyIsNotHeldDown() and controlKeyIsNotHeldDown()
	end

---

	if inputCharacter == inputCharacters[","] and controlModifierIsActive() then
		decrementScaleTonicNoteAction()
	end

	if inputCharacter == inputCharacters["."] and controlModifierIsActive() then
		incrementScaleTonicNoteAction()
	end

	if inputCharacter == inputCharacters["<"] and controlModifierIsActive() then
		decrementScaleTypeAction()
	end

	if inputCharacter == inputCharacters[">"] and controlModifierIsActive() then
		incrementScaleTypeAction()
	end


	if operatingSystem == "win64" or operatingSystem == "win32" then

		if inputCharacter == inputCharacters[","] and shiftKeyIsNotHeldDown() and optionModifierIsActive() then
			halveGridSize()
		end

		if inputCharacter == inputCharacters["."] and shiftKeyIsNotHeldDown() and optionModifierIsActive() then
			doubleGridSize()
		end

		if inputCharacter == inputCharacters[","] and shiftKeyIsHeldDown() and optionModifierIsActive() then
			decrementOctaveAction()
		end

		if inputCharacter == inputCharacters["."] and shiftKeyIsHeldDown() and optionModifierIsActive() then
			incrementOctaveAction()
		end

		--

		if inputCharacter == inputCharacters[","] and shiftKeyIsNotHeldDown() and commandModifierIsActive() then
			decrementChordTypeAction()
		end

		if inputCharacter == inputCharacters["."] and shiftKeyIsNotHeldDown() and commandModifierIsActive() then
			incrementChordTypeAction()
		end

		if inputCharacter == inputCharacters[","] and shiftKeyIsHeldDown() and commandModifierIsActive() then
			decrementChordInversionAction()
		end

		if inputCharacter == inputCharacters["."] and shiftKeyIsHeldDown() and commandModifierIsActive() then
			incrementChordInversionAction()
		end

	else

		if inputCharacter == inputCharacters[","] and optionModifierIsActive() then
			halveGridSize()
		end

		if inputCharacter == inputCharacters["."] and optionModifierIsActive() then
			doubleGridSize()
		end

		if inputCharacter == inputCharacters["<"] and optionModifierIsActive() then
			decrementOctaveAction()
		end

		if inputCharacter == inputCharacters[">"] and optionModifierIsActive() then
			incrementOctaveAction()
		end

		--

		if inputCharacter == inputCharacters[","] and commandModifierIsActive() then
			decrementChordTypeAction()
		end

		if inputCharacter == inputCharacters["."] and commandModifierIsActive() then
			incrementChordTypeAction()
		end

		if inputCharacter == inputCharacters["<"] and commandModifierIsActive() then
			decrementChordInversionAction()
		end

		if inputCharacter == inputCharacters[">"] and commandModifierIsActive() then
			incrementChordInversionAction()
		end
	end
end
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/TK Scripts/Midi/TK_ChordGun"

Interface = {}
Interface.__index = Interface

local dockerXPadding = 0
local dockerYPadding = 0

function Interface:init(name)

  local self = {}
  setmetatable(self, Interface)

  self.name = name
  self.x = getInterfaceXPosition()
  self.y = getInterfaceYPosition()
  

  local dynamicBaseWidth = getDynamicBaseWidth()
  local minWidth = dynamicBaseWidth
  local minHeight = baseHeight
  

  if interfaceWidth > 50 then
    self.width = interfaceWidth
  else
    self.width = minWidth
  end
  
  if interfaceHeight > 50 then
    self.height = interfaceHeight
  else
    self.height = minHeight
  end
  
  self.lastWidth = self.width
  self.lastHeight = self.height

  self.elements = {}

  return self
end

function Interface:restartGui()
	self.elements = {}
	

	local dynamicBaseWidth = getDynamicBaseWidth()
	local minWidth = dynamicBaseWidth
	local minHeight = baseHeight
	

	self.width = gfx.w
	self.height = gfx.h
	
	self.lastWidth = self.width
	self.lastHeight = self.height
	self:startGui()
end

local function getDockerXPadding()

	if gfx.w <= gfx.w then
		return 0
	end

	return 0
end

function Interface:startGui()

	currentWidth = gfx.w
	dockerXPadding = getDockerXPadding()

	self:addMainWindow()
	self:addDocker()
	self:addTopFrame()
	self:addBottomFrame()	
end

function Interface:addMainWindow()

	gfx.clear = hexToNative(getThemeColor("background"))

	local dockState = 0

  if windowShouldBeDocked() then
    dockState = getDockState()
  end
  
	gfx.init(self.name, self.width, self.height, dockState, self.x, self.y)
	

  applyDefaultFont()
end

function Interface:addDocker()

	local docker = Docker:new()
	table.insert(self.elements, docker)
end

function Interface:addChordButton(buttonText, x, y, width, height, scaleNoteIndex, chordTypeIndex, chordIsInScale)

	local chordButton = ChordButton:new(buttonText, x, y, width, height, scaleNoteIndex, chordTypeIndex, chordIsInScale)
	table.insert(self.elements, chordButton)
end

function Interface:addHeader(x, y, width, height, getTextCallback, scaleNoteIndex)

	local header = Header:new(x, y, width, height, getTextCallback, scaleNoteIndex)
	table.insert(self.elements, header)
end

function Interface:addFrame(x, y, width, height)

	local frame = Frame:new(x, y, width, height)
	table.insert(self.elements, frame)
end

function Interface:addLabel(x, y, width, height, getTextCallback, options)

  local label = Label:new(x, y, width, height, getTextCallback, options)
	table.insert(self.elements, label)
end

function Interface:addDropdown(x, y, width, height, options, defaultOptionIndex, onSelectionCallback)

	local dropdown = Dropdown:new(x, y, width, height, options, defaultOptionIndex, onSelectionCallback)
	table.insert(self.elements, dropdown)
end

function Interface:addSimpleButton(text, x, y, width, height, onClick, onRightClick, getTooltip, drawBorder, customColorFn, customTextColorFn)

	local button = SimpleButton:new(text, x, y, width, height, onClick, onRightClick, getTooltip, drawBorder, customColorFn, customTextColorFn)
	table.insert(self.elements, button)
end

function Interface:addToggleButton(text, x, y, width, height, getState, onToggle, onRightClick, getTooltip, drawBorder)

	local button = ToggleButton:new(text, x, y, width, height, getState, onToggle, onRightClick, getTooltip, drawBorder)
	table.insert(self.elements, button)
end

function Interface:addCycleButton(x, y, width, height, options, getCurrentIndex, onCycle, drawBorder)

	local button = CycleButton:new(x, y, width, height, options, getCurrentIndex, onCycle, drawBorder)
	table.insert(self.elements, button)
end

function Interface:addPiano(x, y, width, height, startingOctave, numOctaves)

	local piano = PianoKeyboard:new(x, y, width, height, startingOctave, numOctaves)
	table.insert(self.elements, piano)
end

function Interface:addChordInversionValueBox(x, y, width, height)

	local valueBox = ChordInversionValueBox:new(x, y, width, height)
	table.insert(self.elements, valueBox)
end

function Interface:addOctaveValueBox(x, y, width, height)

	local valueBox = OctaveValueBox:new(x, y, width, height)
	table.insert(self.elements, valueBox)
end

function Interface:updateElements()

  handleSlotDropdownInput()
  
  for _, element in pairs(self.elements) do
    applyDefaultFont()
    element:update()
  end
	
	drawSlotSettingsDropdown()
	renderPendingTooltips()
end

function handleMidiTriggers()
  if not midiTriggerEnabled then return end
  
  if midiTriggerLearnTarget then
    for note = 0, 127 do
      if externalMidiNotes[note] then
        if midiTriggerLearnTarget.isColumn then
          setMidiTriggerColumnMapping(note, midiTriggerLearnTarget.columnIndex)
        else
          setMidiTriggerMapping(note, midiTriggerLearnTarget.scaleNoteIndex, midiTriggerLearnTarget.chordTypeIndex)
        end
        midiTriggerLearnTarget = nil
        return
      end
    end
  end

  if midiTriggerMode == 1 then
    for note, mapping in pairs(midiTriggerMappings) do
      local velocity = externalMidiNotes[note]
      local isPressed = velocity ~= nil
      
      if isPressed then
        if not midiTriggerState[note] then
          if mapping.scaleNoteIndex <= #scaleNotes then
             setSelectedScaleNote(mapping.scaleNoteIndex)
             setSelectedChordType(mapping.scaleNoteIndex, mapping.chordTypeIndex)
             previewScaleChord(velocity)
             activeTriggerNote = note
          end
          midiTriggerState[note] = true
        end
      else
        if midiTriggerState[note] then
            midiTriggerState[note] = false
            if activeTriggerNote == note then
                local fallbackNote = nil
                local fallbackMapping = nil
                
                for tNote, tMapping in pairs(midiTriggerMappings) do
                    if midiTriggerState[tNote] then
                        fallbackNote = tNote
                        fallbackMapping = tMapping
                        break
                    end
                end
                
                if fallbackNote and fallbackMapping and fallbackMapping.scaleNoteIndex <= #scaleNotes then
                    local fallbackVel = externalMidiNotes[fallbackNote] or 96
                    setSelectedScaleNote(fallbackMapping.scaleNoteIndex)
                    setSelectedChordType(fallbackMapping.scaleNoteIndex, fallbackMapping.chordTypeIndex)
                    previewScaleChord(fallbackVel)
                    activeTriggerNote = fallbackNote
                else
                    stopNotesFromPlaying()
                    activeTriggerNote = nil
                end
            end
        end
      end
    end
  else
    for note, columnIndex in pairs(midiTriggerColumnMappings) do
      local velocity = externalMidiNotes[note]
      local isPressed = velocity ~= nil
      
      if isPressed then
        if not midiTriggerState[note] then
          if columnIndex <= #scaleNotes then
             setSelectedScaleNote(columnIndex)
             previewScaleChord(velocity)
             activeTriggerNote = note
          end
          midiTriggerState[note] = true
        end
      else
        if midiTriggerState[note] then
            midiTriggerState[note] = false
            if activeTriggerNote == note then
                local fallbackNote = nil
                local fallbackCol = nil
                
                for tNote, tCol in pairs(midiTriggerColumnMappings) do
                    if midiTriggerState[tNote] then
                        fallbackNote = tNote
                        fallbackCol = tCol
                        break
                    end
                end
                
                if fallbackNote and fallbackCol and fallbackCol <= #scaleNotes then
                    local fallbackVel = externalMidiNotes[fallbackNote] or 96
                    setSelectedScaleNote(fallbackCol)
                    previewScaleChord(fallbackVel)
                    activeTriggerNote = fallbackNote
                else
                    stopNotesFromPlaying()
                    activeTriggerNote = nil
                end
            end
        end
      end
    end
  end
end

function Interface:update()

  processExternalMidiInput()
  handleMidiTriggers()
  
  if syncPlayEnabled then
    local playState = reaper.GetPlayState()
    local isPlaying = (playState & 1) == 1
    
    if isPlaying and not progressionPlaying then
      startProgressionPlayback()
    elseif not isPlaying and progressionPlaying then
      stopProgressionPlayback()
    end
  end

	updateProgressionPlayback()

	self:updateElements()
	gfx.update()

	if not mouseButtonIsNotPressedDown and leftMouseButtonIsNotHeldDown() and (gfx.mouse_cap & 2 ~= 2) then
		mouseButtonIsNotPressedDown = true
	end

	if scaleTonicNote ~= getScaleTonicNote() then
		scaleTonicNote = getScaleTonicNote()
		updateScaleData()
		self:restartGui()
	end

	if scaleType ~= getScaleType() then
		scaleType = getScaleType()
		updateScaleData()
		self:restartGui()
	end

	if currentWidth ~= gfx.w then
		self:restartGui()
	end

	if guiShouldBeUpdated then
		
		self:restartGui()
		guiShouldBeUpdated = false
	end


  local currentDockState = gfx.dock(-1)
  if getDockState() ~= currentDockState then
    setDockState(currentDockState)
  end

	local _, xpos, ypos, _, _ = gfx.dock(-1,0,0,0,0)
	setInterfaceXPosition(xpos)
	setInterfaceYPosition(ypos)

end

local workingDirectory = reaper.GetResourcePath() .. "/Scripts/TK Scripts/Midi/TK_ChordGun"

local windowWidth = 775

scaleNames = {}
for key, scale in ipairs(scales) do
  table.insert(scaleNames, scale['name'])
end













local scaleLabelWidth = nil
local octaveLabelWidth = nil

local function getTopFrameContentLeft(xMargin)
  return math.max(s(2), xMargin - s(6))
end

local function getTopFrameContentRight(xMargin)
  return gfx.w - xMargin - s(2)
end

local function getPatternStringFromIntervals(intervals)
    local pattern = ""
    local currentNote = 0 -- 0 is root
    local notesInScale = {[0] = true}
    
    for _, interval in ipairs(intervals) do
        currentNote = currentNote + interval
        if currentNote < 12 then
            notesInScale[currentNote] = true
        end
    end
    
    for i = 0, 11 do
        if notesInScale[i] then
            pattern = pattern .. "1"
        else
            pattern = pattern .. "0"
        end
    end
    return pattern
end

function syncWithMidiEditor()
    local hwnd = reaper.MIDIEditor_GetActive()
    if not hwnd then 
        reaper.ShowMessageBox("No active MIDI Editor found.\n\nOpen a MIDI Editor to sync Key Snap settings.", "Sync Failed", 0)
        return 
    end

    -- 1. Check if Key Snap is enabled
    local enabled = reaper.MIDIEditor_GetSetting_int(hwnd, "scale_enabled")
    if enabled ~= 1 then
        reaper.ShowMessageBox("Key Snap is not enabled in the MIDI Editor.\n\nPlease enable 'Scale' at the bottom of the MIDI Editor and select a key.", "Sync Failed", 0)
        return
    end

    -- 2. Get Root Note (0=C, 1=C#, etc)
    local root = reaper.MIDIEditor_GetSetting_int(hwnd, "scale_root") 
    local newTonic = root + 1 -- ChordGun uses 1-12

    -- 3. Get Scale Definition
    local retval, scaleString = reaper.MIDIEditor_GetSetting_str(hwnd, "scale", "")
    
    -- Parse REAPER scale string to a bitmask (e.g. "102034050607" -> "101011010101")
    local targetPattern = ""
    if retval and scaleString and type(scaleString) == "string" and #scaleString >= 12 then
        local cleanStr = scaleString:match("([%w]+)$") or scaleString
        if #cleanStr >= 12 then
            cleanStr = cleanStr:sub(1, 12) -- Take first 12
            for i = 1, 12 do
                local char = cleanStr:sub(i, i)
                if char == "0" then
                    targetPattern = targetPattern .. "0"
                else
                    targetPattern = targetPattern .. "1"
                end
            end
        end
    end

    -- 4. Find matching scale in ChordGun database
    local foundSystemIndex = nil
    local foundScaleIndex = nil
    
    if targetPattern ~= "" then
        -- First pass: Try to find exact match in current system first (to prevent jumping systems unnecessarily)
        local currentSysIdx = getScaleSystemIndex()
        local currentSystem = scaleSystems[currentSysIdx]
        if currentSystem and currentSystem.scales then
            for tIdx, scale in ipairs(currentSystem.scales) do
                local scalePattern = scale.pattern
                if not scalePattern and scale.intervals then
                    scalePattern = getPatternStringFromIntervals(scale.intervals)
                end
                
                if scalePattern == targetPattern then
                    foundSystemIndex = currentSysIdx
                    foundScaleIndex = tIdx
                    break
                end
            end
        end

        -- Second pass: If not found in current system, search all systems
        if not foundSystemIndex then
            for sIdx, system in ipairs(scaleSystems) do
                if system.scales then
                    for tIdx, scale in ipairs(system.scales) do
                        local scalePattern = scale.pattern
                        if not scalePattern and scale.intervals then
                            scalePattern = getPatternStringFromIntervals(scale.intervals)
                        end
                        
                        if scalePattern == targetPattern then
                            foundSystemIndex = sIdx
                            foundScaleIndex = tIdx
                            break
                        end
                    end
                end
                if foundSystemIndex then break end
            end
        end
    end

    -- 5. Apply Settings
    setScaleTonicNote(newTonic)
    
    if foundSystemIndex and foundScaleIndex then
        setScaleSystemIndex(foundSystemIndex)
        setScaleWithinSystemIndex(foundScaleIndex)
        
        local flatIndex = getScaleIndexFromSystemIndices(foundSystemIndex, foundScaleIndex)
        setScaleType(flatIndex)
        
        -- Notify user of success
        local scaleName = scaleSystems[foundSystemIndex].scales[foundScaleIndex].name
        reaper.Help_Set("Synced to: " .. notes[newTonic] .. " " .. scaleName, true)
    else
        -- If no match found, notify user but still sync Tonic
        if targetPattern ~= "" then
             reaper.MB("Synced Tonic to " .. notes[newTonic] .. ".\n\nHowever, the Scale Type could not be matched to any known scale in ChordGun.\n(Pattern: " .. targetPattern .. ")", "Sync Partial", 0)
        end
    end
    
    -- Reset UI to reflect change
    setSelectedScaleNote(1)
    setChordText("")
    resetSelectedChordTypes()
    resetChordInversionStates()
    updateScaleData()
    updateScaleDegreeHeaders()
    
    guiShouldBeUpdated = true
end

function Interface:addTopFrame()

	local keySelectionFrameHeight = s(25)
	self.keySelectionFrameHeight = keySelectionFrameHeight
	local xMargin = s(8)
	local yMargin = s(8)
	local xPadding = s(16)
	local yPadding = s(5)
	local horizontalMargin = s(8)
	local scaleTonicNoteWidth = s(50)
	local scaleSystemWidth = s(150)
	local scaleTypeWidth = s(150)
	local octaveValueBoxWidth = s(55)
	local syncButtonWidth = s(40) -- Width for the new Sync button

	self:addFrame(xMargin+dockerXPadding, yMargin, self.width - 2 * xMargin, keySelectionFrameHeight)
  self:addScaleLabel(xMargin, yMargin, xPadding, yPadding)
	self:addScaleTonicNoteDropdown(xMargin, yMargin, xPadding, yPadding, horizontalMargin, scaleTonicNoteWidth)
	
	self:addScaleSystemDropdown(xMargin, yMargin, xPadding, yPadding, horizontalMargin, scaleTonicNoteWidth, scaleSystemWidth)
	self:addScaleTypeDropdown(xMargin, yMargin, xPadding, yPadding, horizontalMargin, scaleTonicNoteWidth, scaleSystemWidth, scaleTypeWidth)

	-- Add Sync Button (Moved after Scale Type Dropdown)
	local contentLeft = getTopFrameContentLeft(xMargin)
	local spacingAfterLabel = math.max(s(2), horizontalMargin - s(8))
	local scaleTonicNoteXpos = contentLeft + scaleLabelWidth + spacingAfterLabel
	local scaleSystemXpos = scaleTonicNoteXpos + scaleTonicNoteWidth + horizontalMargin
	local scaleTypeXpos = scaleSystemXpos + scaleSystemWidth + horizontalMargin
	
	local syncButtonX = scaleTypeXpos + scaleTypeWidth + s(4)
	local syncButtonY = yMargin + yPadding + s(1)
	local syncButtonHeight = s(15)

	self:addSimpleButton("Sync", syncButtonX+dockerXPadding, syncButtonY, syncButtonWidth, syncButtonHeight, 
			function() syncWithMidiEditor() end, 
			nil, 
			function() return "Click: Sync ChordGun Tonic to MIDI Editor Key Snap" end, 
			true
	)

	-- Calculate effective width to shift subsequent labels (if any)
	local effectiveTypeWidth = scaleTypeWidth + syncButtonWidth + s(4)

	self:addScaleNotesTextLabel(xMargin, yMargin, xPadding, yPadding, horizontalMargin, scaleTonicNoteWidth, scaleSystemWidth, effectiveTypeWidth)
  self:addOctaveLabel(xMargin, yMargin, yPadding, octaveValueBoxWidth)
	self:addOctaveSelectorValueBox(yMargin, xMargin, xPadding, octaveValueBoxWidth)
end

local function topButtonWidth()
  return sx(75)
end

local function topButtonHeight()
  return sy(18)
end

local function topButtonSpacing()
  return sx(1)
end

local function topButtonYPos(yMargin)
  return yMargin + sy(6)
end

local function topButtonXPos(xMargin, xPadding, index)
  return xMargin + xPadding + (topButtonWidth() + topButtonSpacing()) * index
end

function Interface:addHoldButton(xMargin, yMargin, xPadding)

  local buttonWidth = topButtonWidth()
  local buttonHeight = topButtonHeight()
  local buttonXpos = topButtonXPos(xMargin, xPadding, 0)
  local buttonYpos = topButtonYPos(yMargin)
	
	local getHoldState = function() return holdModeEnabled end
	local onToggle = function()
		holdModeEnabled = not holdModeEnabled
	end
	local getTooltip = function() return "Click: Toggle hold mode (notes continue after release)" end
	
  self:addToggleButton("Hold", buttonXpos+dockerXPadding, buttonYpos, buttonWidth, buttonHeight, getHoldState, onToggle, nil, getTooltip)
end

function Interface:addKillButton(xMargin, yMargin, xPadding)

  local buttonWidth = topButtonWidth()
  local buttonHeight = topButtonHeight()
  local buttonXpos = topButtonXPos(xMargin, xPadding, 1)
  local buttonYpos = topButtonYPos(yMargin)
	
	local onClick = function()
		stopAllNotesFromPlaying()
		currentlyHeldButton = nil
		lastPlayedChord = nil
	end
	local getTooltip = function() return "Click: Stop all playing notes" end
	
  self:addSimpleButton("Kill", buttonXpos+dockerXPadding, buttonYpos, buttonWidth, buttonHeight, onClick, nil, getTooltip)
end

function Interface:addStrumButton(xMargin, yMargin, xPadding)

  local buttonWidth = topButtonWidth()
  local buttonHeight = topButtonHeight()
  local buttonXpos = topButtonXPos(xMargin, xPadding, 2)
  local buttonYpos = topButtonYPos(yMargin)
	
	local getStrumState = function() 
		return strumEnabled 
	end
	local onToggle = function()
		strumEnabled = not strumEnabled
    if strumEnabled then arpEnabled = false end
	end
	local onCtrlClick = function()

		local retval, userInput = reaper.GetUserInputs("Strum Settings", 1, "Delay (ms) [10-500]:,extrawidth=100", tostring(strumDelayMs))
		if retval then
			local newDelay = tonumber(userInput)
			if newDelay and newDelay >= 10 and newDelay <= 500 then
				strumDelayMs = newDelay
			else
				reaper.ShowMessageBox("Please enter a value between 10 and 500 ms", "Invalid Input", 0)
			end
		end
	end
	local getTooltip = function() return "Click: Toggle strum mode | Ctrl+Click: Set strum delay" end
	
  self:addToggleButton("Strum", buttonXpos+dockerXPadding, buttonYpos, buttonWidth, buttonHeight, getStrumState, onToggle, onCtrlClick, getTooltip)
end

function Interface:addArpButton(xMargin, yMargin, xPadding)

  local buttonWidth = topButtonWidth()
  local buttonHeight = topButtonHeight()
  local buttonXpos = topButtonXPos(xMargin, xPadding, 3)
  local buttonYpos = topButtonYPos(yMargin)
	
	local getArpState = function() 
		return arpEnabled 
	end
	local onToggle = function()
		arpEnabled = not arpEnabled
    if arpEnabled then strumEnabled = false end
	end
	local onRightClick = function()
    if ctrlModifierIsHeldDown() then
      local menu = "#Arp Speed|"
      menu = menu .. (arpSpeedMode == "grid" and arpGrid == "1/4" and "!" or "") .. "1/4|"
      menu = menu .. (arpSpeedMode == "grid" and arpGrid == "1/8" and "!" or "") .. "1/8|"
      menu = menu .. (arpSpeedMode == "grid" and arpGrid == "1/16" and "!" or "") .. "1/16|"
      menu = menu .. (arpSpeedMode == "grid" and arpGrid == "1/32" and "!" or "") .. "1/32|"
      menu = menu .. (arpSpeedMode == "grid" and arpGrid == "1/64" and "!" or "") .. "1/64|"
      menu = menu .. (arpSpeedMode == "ms" and "!" or "") .. "Custom (" .. arpSpeedMs .. "ms)..."
      
      gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
      local selection = gfx.showmenu(menu)
      if selection > 1 then
        if selection == 2 then arpSpeedMode = "grid"; arpGrid = "1/4"
        elseif selection == 3 then arpSpeedMode = "grid"; arpGrid = "1/8"
        elseif selection == 4 then arpSpeedMode = "grid"; arpGrid = "1/16"
        elseif selection == 5 then arpSpeedMode = "grid"; arpGrid = "1/32"
        elseif selection == 6 then arpSpeedMode = "grid"; arpGrid = "1/64"
        elseif selection == 7 then
          local retval, userInput = reaper.GetUserInputs("Arp Speed", 1, "Speed (ms):,extrawidth=100", tostring(arpSpeedMs))
          if retval then
            local newSpeed = tonumber(userInput)
            if newSpeed and newSpeed >= 10 and newSpeed <= 2000 then
              arpSpeedMs = newSpeed
              arpSpeedMode = "ms"
            end
          end
        end
      end
    else
      local menu = "#Arp Mode|"
      menu = menu .. (arpMode == 1 and "!" or "") .. "Up|"
      menu = menu .. (arpMode == 2 and "!" or "") .. "Down|"
      menu = menu .. (arpMode == 3 and "!" or "") .. "Up/Down|"
      menu = menu .. (arpMode == 5 and "!" or "") .. "Down/Up|"
      menu = menu .. (arpMode == 4 and "!" or "") .. "Random"
      
      gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
      local selection = gfx.showmenu(menu)
      if selection > 1 then
        if selection == 2 then arpMode = 1
        elseif selection == 3 then arpMode = 2
        elseif selection == 4 then arpMode = 3
        elseif selection == 5 then arpMode = 5
        elseif selection == 6 then arpMode = 4
        end
      end
    end
	end
	local getTooltip = function() return "Click: Toggle Arp | R-Click: Mode | Ctrl+Click: Speed" end
	
  self:addToggleButton("Arp", buttonXpos+dockerXPadding, buttonYpos, buttonWidth, buttonHeight, getArpState, onToggle, onRightClick, getTooltip)
end

function Interface:addVoiceLeadingButton(xMargin, yMargin, xPadding)

  local buttonWidth = topButtonWidth()
  local buttonHeight = topButtonHeight()
  local buttonXpos = topButtonXPos(xMargin, xPadding, 4)
  local buttonYpos = topButtonYPos(yMargin)
  
  local getState = function() return voiceLeadingEnabled end
  local onToggle = function()
    voiceLeadingEnabled = not voiceLeadingEnabled
    if not voiceLeadingEnabled then lastPlayedNotes = {} end
  end
  local getTooltip = function() return "Auto Voice Leading: Automatically chooses inversions for smooth transitions" end
  
  self:addToggleButton("Lead", buttonXpos+dockerXPadding, buttonYpos, buttonWidth, buttonHeight, getState, onToggle, nil, getTooltip)
end

function Interface:addScaleFilterButton(xMargin, yMargin, xPadding, opts)

  opts = opts or {}
  local buttonWidth = opts.width or topButtonWidth()
  local buttonHeight = opts.height or topButtonHeight()
  local buttonXpos
  local buttonYpos

  if opts.x and opts.y then
    buttonXpos = opts.x
    buttonYpos = opts.y
  else
    buttonXpos = topButtonXPos(xMargin, xPadding, 4)
    buttonYpos = topButtonYPos(yMargin)
  end

  local getText = function()
    return getScaleFilterModeText()
  end

  local onClick = function()
    cycleScaleFilterMode()
  end

  local getTooltip = function()
    return "Click: Cycle filter mode (Off → Filter → Remap)\nFilter: blocks non-scale notes\nRemap: maps white keys to scale notes"
  end

  local applyDocker = opts.applyDockerPadding ~= false
  local finalX = buttonXpos + (applyDocker and dockerXPadding or 0)
  self:addSimpleButton(getText, finalX, buttonYpos, buttonWidth, buttonHeight, onClick, nil, getTooltip, opts.drawBorder)
end

function Interface:addNoteLengthControl(xPos, yPos, options)

  options = options or {}
  local showLabel = options.showLabel ~= false
  local customWidth = options.buttonWidth

  local labelWidth = showLabel and sx(36) or 0
  local buttonWidth = customWidth or sx(78)
  local buttonHeight = sy(18)
  local spacing = showLabel and sx(4) or 0

  if showLabel then
    local labelX = xPos + dockerXPadding
    self:addLabel(labelX, yPos + sy(2), labelWidth, buttonHeight, function() return "LEN:" end)
  end

  local buttonX = xPos + labelWidth + spacing + dockerXPadding
  self:addDropdown(
    buttonX,
    yPos,
    buttonWidth,
    buttonHeight,
    noteLengthLabels,
    getNoteLengthIndex(),
    function(newIndex)
      setNoteLengthIndex(newIndex)
    end
  )
end

function Interface:addFifthWheelButton(xMargin, yMargin, xPadding)

  local buttonWidth = topButtonWidth()
  local buttonHeight = topButtonHeight()
  local buttonXpos = topButtonXPos(xMargin, xPadding, 4)
  local buttonYpos = topButtonYPos(yMargin)
	
	local getCircleState = function() return fifthWheelWindowOpen end
	local onToggle = function()
		if fifthWheelWindowOpen then

			reaper.SetExtState("TK_ChordGun_FifthWheel", "forceClose", "1", false)
			fifthWheelWindowOpen = false
		else
			showFifthWheel()
		end
	end
	local getTooltip = function() return "Toggle Circle of Fifths\n\nVisual guide to key relationships\nClick any note to change tonic" end
	
  self:addToggleButton("Circle", buttonXpos+dockerXPadding, buttonYpos, buttonWidth, buttonHeight, getCircleState, onToggle, nil, getTooltip)
end

function Interface:addFontButton(xMargin, yMargin, xPadding, rowIndex, colIndex)
  rowIndex = rowIndex or 0
  colIndex = colIndex or 5

  local buttonWidth = topButtonWidth()
  local buttonHeight = topButtonHeight()
  local buttonXpos = topButtonXPos(xMargin, xPadding, colIndex)
  local buttonYpos = topButtonYPos(yMargin) + (rowIndex * (buttonHeight + sy(4)))
	
	local getMonoState = function() 
    return reaper.GetExtState("TK_ChordGun", "useMonospaceFont") ~= "0"
  end
  
	local onToggle = function()
    local current = getMonoState()

    reaper.SetExtState("TK_ChordGun", "useMonospaceFont", current and "0" or "1", true)

    guiShouldBeUpdated = true
	end
  
	local getTooltip = function() return "Toggle Monospace Font\n\nSwitch between Arial and Fixed-Width font\n(Better for alignment/tables)" end
	
  self:addToggleButton("Mono", buttonXpos+dockerXPadding, buttonYpos, buttonWidth, buttonHeight, getMonoState, onToggle, nil, getTooltip)
end

function Interface:addRemapButton(xMargin, yMargin, xPadding, rowIndex, colIndex)
  local buttonWidth = topButtonWidth()
  local buttonHeight = topButtonHeight()
  local buttonXpos = topButtonXPos(xMargin, xPadding, colIndex)
  local buttonYpos = topButtonYPos(yMargin) + (rowIndex * (buttonHeight + sy(4)))

  local getRemapState = function() 

    return scaleFilterMode == 2 
  end
  
  local onToggle = function()
    if scaleFilterMode == 2 then
      scaleFilterMode = 0
    else
      scaleFilterMode = 2
    end
    reaper.gmem_write(0, scaleFilterMode)
    reaper.SetExtState("TK_ChordGun", "scaleFilterMode", tostring(scaleFilterMode), true)
  end
  
  local getTooltip = function() return "Toggle Remap Mode\n\nMaps white keys to scale notes.\n(Requires TK Scale Filter JSFX)" end
  
  self:addToggleButton("Remap", buttonXpos+dockerXPadding, buttonYpos, buttonWidth, buttonHeight, getRemapState, onToggle, nil, getTooltip)
end

function Interface:addSetupButton(xMargin, yMargin, xPadding, rowIndex, colIndex)
  local buttonWidth = topButtonWidth()
  local buttonHeight = topButtonHeight()
  local buttonXpos = topButtonXPos(xMargin, xPadding, colIndex)
  local buttonYpos = topButtonYPos(yMargin) + (rowIndex * (buttonHeight + sy(4)))

  local onClick = function()
      local track = reaper.GetSelectedTrack(0, 0)
      if not track then
          reaper.ShowMessageBox("Please select a track first!", "No Track Selected", 0)
          return
      end
      

      local inputFxCount = reaper.TrackFX_GetRecCount(track)
      for i = 0, inputFxCount - 1 do
          local retval, fxName = reaper.TrackFX_GetFXName(track, i + 0x1000000, "")
          if fxName and fxName:match("TK Scale Filter") then
              reaper.ShowMessageBox("TK Scale Filter is already on this track's Input FX!", "Already Setup", 0)
              return
          end
      end
      

      local fxIndex = reaper.TrackFX_AddByName(track, "JS: TK_Scale_Filter", true, -1000 - 0x1000000)
      if fxIndex >= 0 then
          reaper.ShowMessageBox(
              "TK Scale Filter added to Input FX successfully!\n\n" ..
              "The filter/remap modes will now work with your MIDI input.",
              "Setup Complete",
              0
          )
      else
          reaper.ShowMessageBox(
              "Could not add TK Scale Filter.\n\n" ..
              "Make sure 'TK_Scale_Filter.jsfx' is in your REAPER Effects folder.",
              "Setup Failed",
              0
          )
      end
  end
  
  local getTooltip = function()
      return "Click: Add TK Scale Filter to selected track's Input FX\n\n" ..
             "Yellow text indicates JSFX is active on current track."
  end
  
  -- Custom color function to check for JSFX presence
  local customColorFn = function()
      local track = reaper.GetSelectedTrack(0, 0)
      if track then
          local inputFxCount = reaper.TrackFX_GetRecCount(track)
          for i = 0, inputFxCount - 1 do
              local retval, fxName = reaper.TrackFX_GetFXName(track, i + 0x1000000, "")
              if fxName and fxName:match("TK Scale Filter") then
                  return "FFD700" -- Gold/Yellow
              end
          end
      end
      return nil -- Default color
  end
  
  self:addSimpleButton("JSFX", buttonXpos+dockerXPadding, buttonYpos, buttonWidth, buttonHeight, onClick, nil, getTooltip, nil, customColorFn)
end

function Interface:addPianoKeyboard(xMargin, yMargin, xPadding, yPadding, headerHeight)

	local pianoWidth = self.width - 2 * xMargin - 2 * xPadding
	local pianoHeight = sy(70)
	local pianoXpos = xMargin + xPadding
	


	local buttonHeight = sy(38)
	local innerSpacing = sx(2)
	local numChordButtons = maxVisibleRows
	local pianoYpos = yMargin + yPadding + headerHeight + (numChordButtons * buttonHeight) + (numChordButtons * innerSpacing) - sy(3) + sy(6)
	



	local currentOctave = getOctave()
	local startNote = (currentOctave - 1) * 12
	
	self:addPiano(pianoXpos+dockerXPadding, pianoYpos, pianoWidth, pianoHeight, startNote, 3)
end

function Interface:addProgressionSlots(xMargin, yMargin, xPadding, yPadding, headerHeight)

	local slotWidth = self.width - 2 * xMargin - 2 * xPadding
  local slotHeight = sy(50)
	local slotXpos = xMargin + xPadding
	

	local buttonHeight = sy(38)
	local innerSpacing = sx(2)
	local numChordButtons = maxVisibleRows
	local pianoHeight = sy(70)
	local pianoYpos = yMargin + yPadding + headerHeight + (numChordButtons * buttonHeight) + (numChordButtons * innerSpacing) - sy(3) + sy(6)
	local slotYpos = pianoYpos + pianoHeight + sy(8)
	
	local slots = ProgressionSlots:new(slotXpos + dockerXPadding, slotYpos, slotWidth, slotHeight)
	table.insert(self.elements, slots)
end

function Interface:addProgressionControls(xMargin, yMargin, xPadding, yPadding, headerHeight)

	local buttonWidth = sx(80)
	local buttonHeight = sy(28)
	local buttonXpos = xMargin + xPadding
  local buttonSpacing = sx(2)
	

	local buttonHeightChord = sy(38)
	local innerSpacing = sx(2)
	local numChordButtons = maxVisibleRows
	local pianoHeight = sy(70)
  local slotHeight = sy(50)
	local pianoYpos = yMargin + yPadding + headerHeight + (numChordButtons * buttonHeightChord) + (numChordButtons * innerSpacing) - sy(3) + sy(6)
	local slotYpos = pianoYpos + pianoHeight + sy(8)
	local buttonYpos = slotYpos + slotHeight + sy(6)
	

  self:addSimpleButton(
    "Play",
		buttonXpos + dockerXPadding,
		buttonYpos,
		buttonWidth,
		buttonHeight,
		function() 
      if syncPlayEnabled then
        reaper.Main_OnCommand(1007, 0) -- Transport: Play
      else
        startProgressionPlayback() 
      end
    end,
		function() 
      syncPlayEnabled = not syncPlayEnabled 
      guiShouldBeUpdated = true
    end,
		function() 
      local state = syncPlayEnabled and "ON" or "OFF"
      return "Click: Start progression playback\nRight-Click: Toggle Sync Play (Current: " .. state .. ")" 
    end,
    true,
    function() return syncPlayEnabled and "3399FF" or nil end
	)
	

  self:addSimpleButton(
    "Stop",
    buttonXpos + dockerXPadding + buttonWidth + buttonSpacing,
		buttonYpos,
		buttonWidth,
		buttonHeight,
		function() 
      if syncPlayEnabled then
        reaper.Main_OnCommand(1016, 0) -- Transport: Stop
      else
        stopProgressionPlayback() 
      end
    end,
		nil,
		function() return "Click: Stop progression playback" end,
    true
	)
	

  self:addSimpleButton(
    "Clear",
    buttonXpos + dockerXPadding + (buttonWidth + buttonSpacing) * 2,
		buttonYpos,
		buttonWidth,
		buttonHeight,
		function() clearChordProgression() end,
		nil,
		function() return "Click: Clear all slots in progression" end,
    true
	)


  self:addSimpleButton(
    "Save",
    buttonXpos + dockerXPadding + (buttonWidth + buttonSpacing) * 3,
		buttonYpos,
		buttonWidth,
		buttonHeight,
		function() saveProgressionPreset() end,
		nil,
		function() return "Click: Save progression as preset" end,
    true
	)
	

  self:addSimpleButton(
    "Load",
    buttonXpos + dockerXPadding + (buttonWidth + buttonSpacing) * 4,
		buttonYpos,
		buttonWidth,
		buttonHeight,
		function() showLoadPresetMenu() end,
		function() showTemplatesMenu() end,
		function() return "Click: Load preset | Right-Click: Progression Templates" end,
    true
	)
	

  local insertInlineX = buttonXpos + dockerXPadding + (buttonWidth + buttonSpacing) * 5
  

  local onInsertRightClick = function()
    local menu = "Export to Chord Track (Text Items)|Export to Project Regions"
    gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
    local selection = gfx.showmenu(menu)
    
    if selection == 1 then
      exportProgressionToTrack()
    elseif selection == 2 then
      exportProgressionToMarkers()
    end
  end

  self:addSimpleButton(
    "Insert",
    insertInlineX,
    buttonYpos,
    buttonWidth,
    buttonHeight,
    function() insertProgressionToMIDI() end,
    onInsertRightClick,
    function() return "Click: Insert MIDI | Right-Click: Export as Text Items or Markers" end,
    true
	)
	


  local totalWidth = self.width - 2 * xMargin - 2 * xPadding
  local scrollBtnWidth = sx(20)
  
  -- Calculate position of the leftmost button in the right-side group (Tooltip/Font)
  -- Right side structure: [Tooltip/Font] [Help/Ratio] [Dock/Circle] [Scroll]
  local col3X = buttonXpos + dockerXPadding + totalWidth - buttonWidth - scrollBtnWidth - buttonSpacing
  local col2X = col3X - buttonSpacing - buttonWidth
  local col1X = col2X - buttonSpacing - buttonWidth
  
  local chordDisplayX = insertInlineX + buttonWidth + buttonSpacing
  local chordDisplayWidth = col1X - buttonSpacing - chordDisplayX
  local chordDisplayHeight = (buttonHeight * 2) + s(1)
  
  local ChordDisplay = {}
  ChordDisplay.x = chordDisplayX
  ChordDisplay.y = buttonYpos
  ChordDisplay.width = chordDisplayWidth
  ChordDisplay.height = chordDisplayHeight
  
  ChordDisplay.update = function(self)
    local x = self.x
    local y = self.y
    local w = self.width
    local h = self.height
    

    setThemeColor("chordDisplayBg")
    gfx.rect(x, y, w, h, false)
    
    -- Draw Track Info
    local track = reaper.GetSelectedTrack(0, 0)
    if track then
        local retval, name = reaper.GetTrackName(track)
        local number = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
        local trackInfo = string.format("%d: %s", number, name)
        
        gfx.setfont(1, "Arial", s(12)) -- Use small font
        setThemeColor("chordDisplayText")
        gfx.x = x + sx(4)
        gfx.y = y + sy(2)
        gfx.drawstr(trackInfo)
    end
    
    -- Draw Preset Info (right side, left of dice button)
    if currentTriggerPreset and midiTriggerEnabled then
        gfx.setfont(1, "Arial", s(12))
        setThemeColor("chordDisplayText")
        local presetText = currentTriggerPreset
        local presetW, presetH = gfx.measurestr(presetText)
        local diceOffset = sy(16) + sx(16)
        gfx.x = x + w - presetW - diceOffset
        gfx.y = y + sy(2)
        gfx.drawstr(presetText)
    end
    
    if recognizedChord and recognizedChord ~= "" then

      local isInScale = false
      if scalePattern and #recognizedChord > 0 then

        local rootStr = recognizedChord:match("^([A-G][#b]?)")
        if rootStr then

          local noteNames = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
          local flatNames = {"C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"}
          for i, name in ipairs(noteNames) do
            if name == rootStr or flatNames[i] == rootStr then
              isInScale = scalePattern[i] or false
              break
            end
          end
        end
      end
      

      if isInScale then
        setThemeColor("chordDisplayRecognized")
      else
        setThemeColor("chordDisplayRecognizedOutOfScale")
      end
      

      local fontSizeVal = fontSize(28)
      gfx.setfont(1, "Arial", fontSizeVal, string.byte('b'))
      local text = recognizedChord
      local textW, textH = gfx.measurestr(text)
      

      while textW > w - s(10) and fontSizeVal > 10 do
          fontSizeVal = fontSizeVal - 2
          gfx.setfont(1, "Arial", fontSizeVal, string.byte('b'))
          textW, textH = gfx.measurestr(text)
      end
      
      gfx.x = x + (w - textW) / 2
      gfx.y = y + (h - textH) / 2
      gfx.drawstr(text)
      

      gfx.setfont(1, "Arial", fontSize(15))
    end
  end
  
  table.insert(self.elements, ChordDisplay)
  
  -- Add Randomize Dice Button (Top Right of Chord Display Box)
  local diceSize = sy(16)
  local diceX = chordDisplayX + chordDisplayWidth - diceSize - sx(4)
  local diceY = buttonYpos + sy(4)
  
  local onDiceRightClick = function()
      local check4 = progressionLength == 4 and "!" or ""
      local check8 = progressionLength == 8 and "!" or ""
      local checkTonic = randomizeStartWithTonic and "!" or ""
      local checkSelected = randomizeUseSelectedChords and "!" or ""
      
      local menu = ">Progression Length|" .. check4 .. "4 Slots|" .. check8 .. "8 Slots|<|" ..
                   checkTonic .. "Always Start on Tonic|" ..
                   checkSelected .. "Use Selected Chord Types|" ..
                   "Clear Progression"
      
      gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
      local selection = gfx.showmenu(menu)
      
      if selection == 1 then 
          progressionLength = 4
          guiShouldBeUpdated = true
      elseif selection == 2 then 
          progressionLength = 8
          guiShouldBeUpdated = true
      elseif selection == 3 then 
          randomizeStartWithTonic = not randomizeStartWithTonic
      elseif selection == 4 then
          randomizeUseSelectedChords = not randomizeUseSelectedChords
      elseif selection == 5 then
          clearChordProgression()
      end
  end
  
  local diceButton = DiceButton:new(
    diceX,
    diceY,
    diceSize,
    function() randomizeProgression() end,
    function() return "Click: Fill empty slots | Right-Click: Settings" end,
    onDiceRightClick
  )
  table.insert(self.elements, diceButton)
  
  local trigY = diceY + diceSize + sy(2)
  local onTrigRightClick = function()
      local chordCount = 0
      for _ in pairs(midiTriggerMappings) do chordCount = chordCount + 1 end
      local colCount = 0
      for _ in pairs(midiTriggerColumnMappings) do colCount = colCount + 1 end
      
      local checkChord = midiTriggerMode == 1 and "!" or ""
      local checkColumn = midiTriggerMode == 2 and "!" or ""
      
      local presets = getChordMapPresets()
      local menu = ">Mode|" .. checkChord .. "Chord Mode (" .. chordCount .. " mapped)|" .. checkColumn .. "Column Mode (" .. colCount .. " mapped)|<|"
      menu = menu .. "Save Preset...|>Load Preset|"
      menu = menu .. "White Keys (C2-B2)|"
      if #presets > 0 then
        for i, p in ipairs(presets) do
          menu = menu .. p .. "|"
        end
      end
      menu = menu .. "<|>Delete Preset|"
      if #presets > 0 then
        for i, p in ipairs(presets) do
          menu = menu .. p .. "|"
        end
      else
        menu = menu .. "#(no presets)|"
      end
      menu = menu .. "<||Clear All Mappings"
      
      gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
      local selection = gfx.showmenu(menu)
      
      if selection == 1 then
          midiTriggerMode = 1
          saveMidiTriggerMappings()
          updateScaleFilterState()
      elseif selection == 2 then
          midiTriggerMode = 2
          saveMidiTriggerMappings()
          updateScaleFilterState()
      elseif selection == 3 then
          local retval, name = reaper.GetUserInputs("Save ChordMap Preset", 1, "Preset Name:", "")
          if retval and name ~= "" then
            name = name:gsub("[^%w%s%-_]", "")
            if saveChordMapPreset(name) then
              reaper.ShowMessageBox("Preset '" .. name .. "' saved!", "Saved", 0)
            end
          end
      elseif selection == 4 then
          loadBuiltInPreset_WhiteKeys7()
      elseif selection >= 5 and selection <= 4 + #presets then
          local presetName = presets[selection - 4]
          if loadChordMapPreset(presetName) then
            reaper.ShowMessageBox("Preset '" .. presetName .. "' loaded!", "Loaded", 0)
          end
      elseif selection >= 5 + #presets and selection <= 4 + #presets * 2 then
          local presetName = presets[selection - 4 - #presets]
          local confirm = reaper.ShowMessageBox("Delete preset '" .. presetName .. "'?", "Confirm Delete", 4)
          if confirm == 6 then
            deleteChordMapPreset(presetName)
          end
      elseif selection == 5 + #presets * 2 then
          midiTriggerMappings = {}
          midiTriggerColumnMappings = {}
          currentTriggerPreset = nil
          saveMidiTriggerMappings()
          updateScaleFilterState()
      end
  end

  local trigButton = MidiTriggerButton:new(
      diceX,
      trigY,
      diceSize,
      function() 
        if not midiTriggerEnabled then
            local track = reaper.GetSelectedTrack(0, 0)
            local jsfxFound = false
            if track then
                local inputFxCount = reaper.TrackFX_GetRecCount(track)
                for i = 0, inputFxCount - 1 do
                    local retval, fxName = reaper.TrackFX_GetFXName(track, i + 0x1000000, "")
                    if fxName and fxName:match("TK Scale Filter") then 
                        jsfxFound = true 
                        break 
                    end
                end
            end
            
            if not jsfxFound then
                local result = reaper.ShowMessageBox("TK Scale Filter JSFX is required for MIDI Trigger Mode to block trigger notes.\n\nIt was not found on the selected track's Input FX.\n\nAdd it now?", "Setup Required", 4)
                if result == 6 then
                    if not track then
                        reaper.ShowMessageBox("Please select a track first!", "No Track Selected", 0)
                        return
                    end
                    local fxIndex = reaper.TrackFX_AddByName(track, "JS: TK_Scale_Filter", true, -1000 - 0x1000000)
                    if fxIndex < 0 then
                        reaper.ShowMessageBox("Could not add TK Scale Filter.", "Setup Failed", 0)
                        return
                    end
                else
                    return
                end
            end
        end

        midiTriggerEnabled = not midiTriggerEnabled 
        updateScaleFilterState()
      end,
      function() 
          local count = 0
          if midiTriggerMode == 1 then
            for _ in pairs(midiTriggerMappings) do count = count + 1 end
          else
            for _ in pairs(midiTriggerColumnMappings) do count = count + 1 end
          end
          local modeName = midiTriggerMode == 1 and "Chord" or "Column"
          return "Click: Toggle MIDI Trigger\nRight-Click: Settings\nMode: " .. modeName .. " (" .. count .. " mapped)" 
      end,
      onTrigRightClick
  )
  table.insert(self.elements, trigButton)
  
  local pinY = trigY + diceSize + sy(2)
  local pinButton = PinButton:new(
      diceX,
      pinY,
      diceSize,
      function() 
        alwaysOnTopEnabled = not alwaysOnTopEnabled
        local dockState = getDockState()
        if alwaysOnTopEnabled then
           -- If docked, undock first? Or just set floating window on top?
           -- Usually dockState 0 is floating.
           -- We can try to use reaper.JS_Window_SetZOrder if available, or just re-init with a specific flag if possible.
           -- Standard trick: re-init window.
           -- But wait, gfx.init doesn't support always on top natively.
           -- Let's try to use the JS_API if available, otherwise show message.
           
           if reaper.JS_Window_SetZOrder then
              local hwnd = reaper.JS_Window_Find(self.name, true)
              if hwnd then
                 reaper.JS_Window_SetZOrder(hwnd, "TOPMOST")
              end
           else
              reaper.ShowMessageBox("Please install 'JS_ReaScriptAPI' extension for 'Always on Top' functionality.", "Missing Extension", 0)
              alwaysOnTopEnabled = false
           end
        else
           if reaper.JS_Window_SetZOrder then
              local hwnd = reaper.JS_Window_Find(self.name, true)
              if hwnd then
                 reaper.JS_Window_SetZOrder(hwnd, "NOTOPMOST")
              end
           end
        end
      end,
      function() return "Click: Toggle Always on Top (Requires JS_API)" end
  )
  table.insert(self.elements, pinButton)
	


	


	


	

  local buttonYposRow2 = buttonYpos + buttonHeight + s(1)
  

  self:addScaleFilterButton(xMargin, yMargin, xPadding, {
    x = buttonXpos + dockerXPadding,
    y = buttonYposRow2,
    width = buttonWidth,
    height = buttonHeight,
    applyDockerPadding = false,
    drawBorder = true
  })
  

  local onSetupClick = function()
      local track = reaper.GetSelectedTrack(0, 0)
      if not track then reaper.ShowMessageBox("Please select a track first!", "No Track Selected", 0) return end
      local inputFxCount = reaper.TrackFX_GetRecCount(track)
      for i = 0, inputFxCount - 1 do
          local retval, fxName = reaper.TrackFX_GetFXName(track, i + 0x1000000, "")
          if fxName and fxName:match("TK Scale Filter") then reaper.ShowMessageBox("TK Scale Filter is already on this track's Input FX!", "Already Setup", 0) return end
      end
      local fxIndex = reaper.TrackFX_AddByName(track, "JS: TK_Scale_Filter", true, -1000 - 0x1000000)
      if fxIndex >= 0 then reaper.ShowMessageBox("TK Scale Filter added to Input FX successfully!", "Setup Complete", 0) else reaper.ShowMessageBox("Could not add TK Scale Filter.", "Setup Failed", 0) end
  end

  local customColorFn = function()
      local track = reaper.GetSelectedTrack(0, 0)
      if track then
          local inputFxCount = reaper.TrackFX_GetRecCount(track)
          for i = 0, inputFxCount - 1 do
              local retval, fxName = reaper.TrackFX_GetFXName(track, i + 0x1000000, "")
              if fxName and fxName:match("TK Scale Filter") then
                  if isLightMode then
                      return "0000FF" -- Blue
                  else
                      return "FFD700" -- Gold/Yellow
                  end
              end
          end
      end
      return nil
  end

  self:addSimpleButton("JSFX", buttonXpos + dockerXPadding + buttonWidth + buttonSpacing, buttonYposRow2, buttonWidth, buttonHeight, onSetupClick, nil, function() return "Click: Add TK Scale Filter to selected track's Input FX\nYellow text indicates JSFX is active." end, true, nil, customColorFn)


  local getBassState = function() return voicingState.bass1 or voicingState.bass2 end
  local onBassToggle = function()
    if voicingState.bass1 or voicingState.bass2 then
      voicingState.bass1 = false
      voicingState.bass2 = false
    else
      voicingState.bass1 = true
    end
    guiShouldBeUpdated = true
  end
  local onBassRightClick = function()
    local checkBass1 = voicingState.bass1 and "!" or ""
    local checkBass2 = voicingState.bass2 and "!" or ""
    local menu = checkBass1 .. "Bass -1|" .. checkBass2 .. "Bass -2"
    gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
    local selection = gfx.showmenu(menu)
    if selection == 1 then
      voicingState.bass1 = true
      voicingState.bass2 = false
    elseif selection == 2 then
      voicingState.bass2 = true
      voicingState.bass1 = false
    end
    if selection > 0 then guiShouldBeUpdated = true end
  end

  self:addToggleButton(
    "Bass",
    buttonXpos + dockerXPadding + (buttonWidth + buttonSpacing) * 2,
    buttonYposRow2,
    buttonWidth,
    buttonHeight,
    getBassState,
    onBassToggle,
    onBassRightClick,
    function() return "Click: Toggle Bass Voicing | Right-Click: Select Bass Mode" end,
    true
  )

  local getDropState = function() return voicingState.drop2 or voicingState.drop3 end
  local onDropToggle = function()
    if voicingState.drop2 or voicingState.drop3 then
      voicingState.drop2 = false
      voicingState.drop3 = false
    else
      voicingState.drop2 = true
    end
    guiShouldBeUpdated = true
  end
  local onDropRightClick = function()
    local checkDrop2 = voicingState.drop2 and "!" or ""
    local checkDrop3 = voicingState.drop3 and "!" or ""
    local menu = checkDrop2 .. "Drop 2|" .. checkDrop3 .. "Drop 3"
    gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
    local selection = gfx.showmenu(menu)
    if selection == 1 then
      voicingState.drop2 = true
      voicingState.drop3 = false
    elseif selection == 2 then
      voicingState.drop3 = true
      voicingState.drop2 = false
    end
    if selection > 0 then guiShouldBeUpdated = true end
  end

  self:addToggleButton(
    "Drop",
    buttonXpos + dockerXPadding + (buttonWidth + buttonSpacing) * 3,
    buttonYposRow2,
    buttonWidth,
    buttonHeight,
    getDropState,
    onDropToggle,
    onDropRightClick,
    function() return "Click: Toggle Drop Voicing | Right-Click: Select Drop Mode" end,
    true
  )


  local onMelodyRightClick = function()
    local checkSlow = melodySettings.density == 1 and "!" or ""
    local checkNorm = melodySettings.density == 2 and "!" or ""
    local checkFast = melodySettings.density == 3 and "!" or ""
    
    local checkLow = melodySettings.octave == 4 and "!" or ""
    local checkMid = melodySettings.octave == 5 and "!" or ""
    local checkHigh = melodySettings.octave == 6 and "!" or ""
    
    local checkChord = not melodySettings.useScaleNotes and "!" or ""
    local checkScale = melodySettings.useScaleNotes and "!" or ""
    
    local menu = ">Rhythm Density|" .. checkSlow .. "Slow|" .. checkNorm .. "Normal|" .. checkFast .. "Fast|<|" ..
                 ">Octave Range|" .. checkLow .. "Low (C3-C4)|" .. checkMid .. "Mid (C4-C5)|" .. checkHigh .. "High (C5-C6)|<|" ..
                 ">Note Selection|" .. checkChord .. "Chord Tones Only|" .. checkScale .. "Include Scale Notes"
                 
    gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
    local selection = gfx.showmenu(menu)
    


    if selection == 1 then melodySettings.density = 1
    elseif selection == 2 then melodySettings.density = 2
    elseif selection == 3 then melodySettings.density = 3

    elseif selection == 4 then melodySettings.octave = 4
    elseif selection == 5 then melodySettings.octave = 5
    elseif selection == 6 then melodySettings.octave = 6

    elseif selection == 7 then melodySettings.useScaleNotes = false
    elseif selection == 8 then melodySettings.useScaleNotes = true
    end
  end

  self:addSimpleButton(
    "Melody",
    buttonXpos + dockerXPadding + (buttonWidth + buttonSpacing) * 4,
    buttonYposRow2,
    buttonWidth,
    buttonHeight,
    function() generateMelodyFromProgression() end,
    onMelodyRightClick,
    function() return "Click: Generate Melody | Right-Click: Melody Settings" end,
    true
  )

  local getThemeState = function() return themeMode > 1 end
  local getThemeText = function()
    if themeMode == 1 then return "Dark"
    elseif themeMode == 2 then return "Light"
    elseif themeMode == 3 then return "Color"
    elseif themeMode == 4 then return "Neon"
    elseif themeMode == 5 then return "Ocean"
    else return "Mono"
    end
  end
  local onThemeToggle = function()
    themeMode = (themeMode % 6) + 1
    isLightMode = (themeMode == 2)
    reaper.SetExtState("TK_ChordGun", "themeMode", tostring(themeMode), true)
    reaper.SetExtState("TK_ChordGun", "lightMode", isLightMode and "1" or "0", true)
    gfx.clear = hexToNative(getThemeColor("background"))
    guiShouldBeUpdated = true
  end
  
  self:addSimpleButton(getThemeText, col3X, buttonYposRow2, buttonWidth, buttonHeight, onThemeToggle, nil, function() return "Theme: Dark / Light / Color / Neon / Ocean / Mono" end, true)
  

  local getMonoState = function() return reaper.GetExtState("TK_ChordGun", "useMonospaceFont") ~= "0" end
  local onMonoToggle = function()
    local current = getMonoState()
    reaper.SetExtState("TK_ChordGun", "useMonospaceFont", current and "0" or "1", true)
    guiShouldBeUpdated = true
  end
  local onFontRightClick = function()
    local menu = "Small (1.0)|Normal (1.25)|Big (1.5)|Bigger (1.75)"
    gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
    local selection = gfx.showmenu(menu)
    
    local newScale = nil
    if selection == 1 then newScale = 1.0
    elseif selection == 2 then newScale = 1.25
    elseif selection == 3 then newScale = 1.5
    elseif selection == 4 then newScale = 1.75
    end
    
    if newScale then
      fontScale = newScale
      reaper.SetExtState("TK_ChordGun", "fontScale", tostring(fontScale), true)
      guiShouldBeUpdated = true
    end
  end



  local getRatioState = function() return reaper.GetExtState("TK_ChordGun", "useFixedRatio") ~= "0" end
  local onRatioToggle = function()
    local current = getRatioState()
    reaper.SetExtState("TK_ChordGun", "useFixedRatio", current and "0" or "1", true)

    if not current then
        local dynWidth = getDynamicBaseWidth()
        local targetH = math.floor(gfx.w * (baseHeight / dynWidth))
        gfx.init("", gfx.w, targetH)
    end
    guiShouldBeUpdated = true
  end

  local onRatioRightClick = function()
    local menu = "Tiny (50%)|Small (75%)|Normal (100%)|Big (125%)|Bigger (150%)|Enormous (200%)"
    gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
    local selection = gfx.showmenu(menu)
    
    local scale = nil
    if selection == 1 then scale = 0.5
    elseif selection == 2 then scale = 0.75
    elseif selection == 3 then scale = 1.0
    elseif selection == 4 then scale = 1.25
    elseif selection == 5 then scale = 1.5
    elseif selection == 6 then scale = 2.0
    end
    
    if scale then
        local dynWidth = getDynamicBaseWidth()
        local newW = math.floor(dynWidth * scale)
        local newH = math.floor(baseHeight * scale)
        

        reaper.SetExtState("TK_ChordGun", "useFixedRatio", "1", true)
        
        gfx.init("", newW, newH)
        guiShouldBeUpdated = true
    end
  end

  local scrollBtnWidth = sx(20)
  local totalWidth = self.width - 2 * xMargin - 2 * xPadding
  local scrollX = buttonXpos + dockerXPadding + totalWidth - scrollBtnWidth
  
  self:addSimpleButton("__ARROW_UP__", scrollX, buttonYpos, scrollBtnWidth, buttonHeight, 
      function() 
          if chordListScrollOffset > 0 then 
              chordListScrollOffset = chordListScrollOffset - 1
              guiShouldBeUpdated = true 
          end
      end, nil, function() return "Scroll Up" end, true)

  self:addSimpleButton("__ARROW_DOWN__", scrollX, buttonYposRow2, scrollBtnWidth, buttonHeight, 
      function() 
          local maxRows = 0
          if scaleChords then
              for _, chords in ipairs(scaleChords) do
                  if #chords > maxRows then maxRows = #chords end
              end
          end
          
          if chordListScrollOffset < maxRows - maxVisibleRows then
              chordListScrollOffset = chordListScrollOffset + 1
              guiShouldBeUpdated = true 
          end
      end, nil, function() return "Scroll Down" end, true)


  local rightAlignX = buttonXpos + dockerXPadding + totalWidth - buttonWidth - scrollBtnWidth - buttonSpacing
  local leftOfRightAlignX = rightAlignX - buttonSpacing - buttonWidth
  
  -- Row 1: Tooltip, Help, Dock, Up Arrow (Up Arrow is already placed at scrollX)
  -- Wait, user said:
  -- Rij 1: Tooltip, help, dock, pijltje naar boven
  -- Rij 2: Font, Ratio, Circle, pijltje naar onder
  -- Currently I have 2 columns of buttons to the left of the arrows?
  -- "Tooltip", "Help", "Dock" -> That's 3 buttons.
  -- "Font", "Ratio", "Circle" -> That's 3 buttons.
  -- So I need 3 columns of buttons to the left of the arrows.
  
  local col3X = rightAlignX -- Closest to arrows
  local col2X = leftOfRightAlignX -- Middle
  local col1X = col2X - buttonSpacing - buttonWidth -- Furthest left
  
  -- Row 1 (Top)
  self:addToggleButton(
    "Tooltip",
    col1X,
    buttonYpos,
    buttonWidth,
    buttonHeight,
    function() return tooltipsEnabled end,
    function()
      tooltipsEnabled = not tooltipsEnabled
    end,
    nil,
    function() return "Toggle tooltips (shows click/modifier actions)" end,
    true
  )

  local onHelpRightClick = function()
    local menu = "GitHub: TouristKiller/TK-Scripts|REAPER Forum: ChordGun Thread"
    gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
    local selection = gfx.showmenu(menu)
    
    if selection == 1 then
      if reaper.CF_ShellExecute then
        reaper.CF_ShellExecute("https://github.com/TouristKiller/TK-Scripts")
      else
        reaper.ShowMessageBox("SWS Extension required to open URLs.", "Error", 0)
      end
    elseif selection == 2 then
      if reaper.CF_ShellExecute then
        reaper.CF_ShellExecute("https://forum.cockos.com/showthread.php?t=213180")
      else
        reaper.ShowMessageBox("SWS Extension required to open URLs.", "Error", 0)
      end
    end
  end

  self:addSimpleButton(
    "Help",
    col2X,
    buttonYpos,
    buttonWidth,
    buttonHeight,
    function() showHelpWindow() end,
    onHelpRightClick,
    function() return "Click: Show Help / Shortcuts | Right-Click: Links" end,
    true
  )
  
  self:addSimpleButton(
    function() return windowIsDocked() and "Undock" or "Dock" end,
		col3X,
		buttonYpos,
		buttonWidth,
		buttonHeight,
		function()
			if windowIsDocked() then
				setWindowShouldBeDocked(false)
				gfx.dock(0)
			else
				setWindowShouldBeDocked(true)
				gfx.dock(1)
			end
			guiShouldBeUpdated = true
		end,
		nil,
    function() return windowIsDocked() and "Click: Undock window" or "Click: Dock window" end,
    true
	)

  -- Row 2 (Bottom)
  -- Font, Ratio, Circle
  
  -- Font Button (Moved from earlier in the code)
  self:addToggleButton("Font", col1X, buttonYposRow2, buttonWidth, buttonHeight, getMonoState, onMonoToggle, onFontRightClick, function() return "Toggle Monospace Font | Right-click: Set Font Scale" end, true)

  -- Ratio Button (Moved from earlier in the code)
  self:addToggleButton("Ratio", col2X, buttonYposRow2, buttonWidth, buttonHeight, getRatioState, onRatioToggle, onRatioRightClick, function() return "Toggle Fixed Aspect Ratio | Right-click: Set Window Size" end, true)

  -- Circle Button
  local getCircleState = function() return fifthWheelWindowOpen end
  local onCircleToggle = function()
    if fifthWheelWindowOpen then
      reaper.SetExtState("TK_ChordGun_FifthWheel", "forceClose", "1", false)
      fifthWheelWindowOpen = false
    else
      showFifthWheel()
    end
  end
  self:addToggleButton("Circle", buttonXpos + dockerXPadding + (buttonWidth + buttonSpacing) * 5, buttonYposRow2, buttonWidth, buttonHeight, getCircleState, onCircleToggle, nil, function() return "Toggle Circle of Fifths" end, true)

	
end

function Interface:addScaleLabel(xMargin, yMargin, xPadding, yPadding)

	local labelText = "Scale:"
	scaleLabelWidth = gfx.measurestr(labelText) * (gfx.w / baseWidth)
  local labelXpos = getTopFrameContentLeft(xMargin)
	local labelYpos = yMargin+yPadding
	local labelHeight = s(16)
	self:addLabel(labelXpos+dockerXPadding, labelYpos, scaleLabelWidth, labelHeight, function() return labelText end)
end

function Interface:addScaleTonicNoteDropdown(xMargin, yMargin, xPadding, yPadding, horizontalMargin, scaleTonicNoteWidth)

  local contentLeft = getTopFrameContentLeft(xMargin)
  local spacingAfterLabel = math.max(s(2), horizontalMargin - s(8))
  local scaleTonicNoteXpos = contentLeft + scaleLabelWidth + spacingAfterLabel
	local scaleTonicNoteYpos = yMargin+yPadding+s(1)
	local scaleTonicNoteHeight = s(15)

	local onScaleTonicNoteSelection = function(i)

		setScaleTonicNote(i)
		setSelectedScaleNote(1)
		setChordText("")
		resetSelectedChordTypes()
		resetChordInversionStates()
		updateScaleData()
		updateScaleDegreeHeaders()
	end

	local scaleTonicNote = getScaleTonicNote()
	self:addDropdown(scaleTonicNoteXpos+dockerXPadding, scaleTonicNoteYpos, scaleTonicNoteWidth, scaleTonicNoteHeight, notes, scaleTonicNote, onScaleTonicNoteSelection)

end

function Interface:addScaleSystemDropdown(xMargin, yMargin, xPadding, yPadding, horizontalMargin, scaleTonicNoteWidth, scaleSystemWidth)

  local contentLeft = getTopFrameContentLeft(xMargin)
  local spacingAfterLabel = math.max(s(2), horizontalMargin - s(8))
  local spacingBetweenDropdowns = math.max(s(4), horizontalMargin - s(4))
  local scaleSystemXpos = contentLeft + scaleLabelWidth + spacingAfterLabel + scaleTonicNoteWidth + spacingBetweenDropdowns
	local scaleSystemYpos = yMargin+yPadding+s(1)
	local scaleSystemHeight = s(15)

	local interfaceRef = self
	
	local onScaleSystemSelection = function(i)
		setScaleSystemIndex(i)
		setScaleWithinSystemIndex(1)
		

		local flatIndex = getScaleIndexFromSystemIndices(i, 1)
		setScaleType(flatIndex)
		
		setSelectedScaleNote(1)
		setChordText("")
		resetSelectedChordTypes()
		resetChordInversionStates()
		updateScaleData()
		updateScaleDegreeHeaders()
		

		interfaceRef:restartGui()
	end
	

	local systemNames = {}
	for _, system in ipairs(scaleSystems) do
		table.insert(systemNames, system.name)
	end
	
	local currentSystemIndex = getScaleSystemIndex()
	
	local dropdown = Dropdown:new(scaleSystemXpos+dockerXPadding, scaleSystemYpos, scaleSystemWidth, scaleSystemHeight, systemNames, currentSystemIndex, onScaleSystemSelection)
    
    local originalUpdate = dropdown.update
    dropdown.update = function(self)
        originalUpdate(self)
        
        if mouseButtonIsNotPressedDown and mouseIsHoveringOver(self) and gfx.mouse_cap == 2 then
            mouseButtonIsNotPressedDown = false
            
            local menu = "Open Reascales Folder...|Rescan Reascales"
            
            gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
            local selection = gfx.showmenu(menu)
            
            local reascaleDir = reaper.GetResourcePath() .. "/Scripts/TK Scripts/Midi/TK_ChordGun/Reascales"
            if reaper.GetOS():match("Win") then reascaleDir = reascaleDir:gsub("/", "\\") end
            
            if selection == 1 then
                if reaper.CF_ShellExecute then
                    reaper.CF_ShellExecute(reascaleDir)
                else
                    os.execute('start "" "' .. reascaleDir .. '"')
                end
            elseif selection == 2 then
                -- Remove old user systems
                for i = #scaleSystems, 1, -1 do
                    if scaleSystems[i].name:match("^User: ") then
                        table.remove(scaleSystems, i)
                    end
                end
                
                -- Reload
                loadUserReascales(scaleSystems)
                
                -- Rebuild flat scales table
                scales = {}
                for _, system in ipairs(scaleSystems) do
                    for _, scale in ipairs(system.scales) do
                        table.insert(scales, scale)
                    end
                end
                
                -- Reset selection and refresh
                setScaleSystemIndex(1)
                onScaleSystemSelection(1)
            end
        end
        
        if tooltipsEnabled and mouseIsHoveringOver(self) then
             queueTooltip("Left-Click: Select System | Right-Click: Manage Reascales", gfx.mouse_x, gfx.mouse_y)
        end
    end
    
    table.insert(self.elements, dropdown)
end

function Interface:addScaleTypeDropdown(xMargin, yMargin, xPadding, yPadding, horizontalMargin, scaleTonicNoteWidth, scaleSystemWidth, scaleTypeWidth)

  local contentLeft = getTopFrameContentLeft(xMargin)
  local spacingAfterLabel = math.max(s(2), horizontalMargin - s(8))
  local spacingBetweenDropdowns = math.max(s(4), horizontalMargin - s(4))
  local scaleTypeXpos = contentLeft + scaleLabelWidth + spacingAfterLabel + scaleTonicNoteWidth + spacingBetweenDropdowns + scaleSystemWidth + spacingBetweenDropdowns
	local scaleTypeYpos = yMargin+yPadding+s(1)
	local scaleTypeHeight = s(15)

	local onScaleTypeSelection = function(i)
		setScaleWithinSystemIndex(i)
		

		local systemIndex = getScaleSystemIndex()
		local flatIndex = getScaleIndexFromSystemIndices(systemIndex, i)
		setScaleType(flatIndex)

		setSelectedScaleNote(1)
		setChordText("")
		resetSelectedChordTypes()
		resetChordInversionStates()
		updateScaleData()
		updateScaleDegreeHeaders()
	end
	

	local systemIndex = getScaleSystemIndex()
	local currentSystem = scaleSystems[systemIndex]
	

	if not currentSystem then
		currentSystem = scaleSystems[1]
		systemIndex = 1
		setScaleSystemIndex(1)
	end
	
	local scaleNames = {}
	for _, scale in ipairs(currentSystem.scales) do
		if scale.isHeader then
			table.insert(scaleNames, "#" .. scale.name)
		else
			table.insert(scaleNames, scale.name)
		end
	end
	
	local currentScaleIndex = getScaleWithinSystemIndex()
	local currentScale = currentSystem.scales[currentScaleIndex]
	

	if not currentScale then
		currentScaleIndex = 1
		currentScale = currentSystem.scales[1]
		setScaleWithinSystemIndex(1)
	end
	
	local dropdown = Dropdown:new(scaleTypeXpos+dockerXPadding, scaleTypeYpos, scaleTypeWidth, scaleTypeHeight, scaleNames, currentScaleIndex, onScaleTypeSelection)
	

	local originalUpdate = dropdown.update
	dropdown.update = function(self)
		originalUpdate(self)
		

		if tooltipsEnabled and mouseIsHoveringOver(self) then
			local tooltip = currentScale.name
			

			if currentScale.description then
				tooltip = tooltip .. "\n\n" .. currentScale.description
			end
			

			if currentScale.intervals then
				tooltip = tooltip .. "\n\nInterval pattern: " .. currentScale.intervals .. " (semitones)"
			end
			
			queueTooltip(tooltip, gfx.mouse_x, gfx.mouse_y)
		end
	end
	
	table.insert(self.elements, dropdown)
end

function Interface:addScaleNotesTextLabel(xMargin, yMargin, xPadding, yPadding, horizontalMargin, scaleTonicNoteWidth, scaleSystemWidth, scaleTypeWidth)

	local getScaleNotesTextCallback = function() return getScaleNotesText() end
  local contentLeft = getTopFrameContentLeft(xMargin)
  local spacingAfterLabel = math.max(s(2), horizontalMargin - s(8))
  local spacingBetweenDropdowns = math.max(s(4), horizontalMargin - s(4))
  local previousControlsRight = contentLeft + scaleLabelWidth + spacingAfterLabel + scaleTonicNoteWidth + spacingBetweenDropdowns + scaleSystemWidth + spacingBetweenDropdowns + scaleTypeWidth
  local scaleNotesXpos = previousControlsRight + s(20)
	local scaleNotesYpos = yMargin+yPadding+s(1)
  local availableWidth = getTopFrameContentRight(xMargin) - scaleNotesXpos - s(70)
  local scaleNotesWidth = math.max(s(200), availableWidth)
	local scaleNotesHeight = s(15)
  self:addLabel(scaleNotesXpos+dockerXPadding, scaleNotesYpos, scaleNotesWidth, scaleNotesHeight, getScaleNotesTextCallback, {align = "left"})
end

function Interface:addOctaveLabel(xMargin, yMargin, yPadding, octaveValueBoxWidth)

	local labelText = "Octave:"
	local octaveLabelWidth = sx(80)
	local labelYpos = yMargin+yPadding+s(1)
	local labelHeight = s(15)
  local contentRight = getTopFrameContentRight(xMargin)
  local spacing = s(13)
  local labelXpos = contentRight - octaveValueBoxWidth - spacing - octaveLabelWidth
	self:addLabel(labelXpos+dockerXPadding, labelYpos, octaveLabelWidth, labelHeight, function() return labelText end, {align = "right"})
end

function Interface:addOctaveSelectorValueBox(yMargin, xMargin, xPadding, octaveValueBoxWidth)

  local contentRight = getTopFrameContentRight(xMargin)
  local pickerLeftShift = s(8)
  local valueBoxXPos = contentRight - octaveValueBoxWidth - pickerLeftShift
	local valueBoxYPos = yMargin + s(6)
	local valueBoxHeight = s(15)
	self:addOctaveValueBox(valueBoxXPos+dockerXPadding, valueBoxYPos, octaveValueBoxWidth, valueBoxHeight)
end
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/TK Scripts/Midi/TK_ChordGun"



DiceButton = {}
DiceButton.__index = DiceButton

function DiceButton:new(x, y, size, onClick, getTooltip, onRightClick)
    local self = {}
    setmetatable(self, DiceButton)
    self.x = x
    self.y = y
    self.width = size
    self.height = size
    self.onClick = onClick
    self.onRightClick = onRightClick
    self.getTooltip = getTooltip
    return self
end

function DiceButton:draw()
    -- Draw background/hover effect
    if mouseIsHoveringOver(self) then
        setThemeColor("topButtonTextHover") -- Use hover color for dots/outline
    else
        setThemeColor("topButtonText") -- Use normal text color
    end

    -- Draw rounded box (simulated with lines/rects or just a rect)
    -- Simple rect for now
    gfx.rect(self.x, self.y, self.width, self.height, 0)
    
    -- Draw 5 dots (Quincunx pattern)
    local dotSize = math.max(1, math.floor(self.width / 10))
    local cx = self.x + self.width / 2
    local cy = self.y + self.height / 2
    local offset = self.width / 4

    -- Center
    gfx.circle(cx, cy, dotSize, 1)
    
    -- Corners
    gfx.circle(cx - offset, cy - offset, dotSize, 1) -- Top-Left
    gfx.circle(cx + offset, cy - offset, dotSize, 1) -- Top-Right
    gfx.circle(cx - offset, cy + offset, dotSize, 1) -- Bottom-Left
    gfx.circle(cx + offset, cy + offset, dotSize, 1) -- Bottom-Right
    
    -- Tooltip
    if tooltipsEnabled and mouseIsHoveringOver(self) and self.getTooltip then
        local tooltip = self.getTooltip()
        if tooltip then
            queueTooltip(tooltip, gfx.mouse_x, gfx.mouse_y)
        end
    end
end

function DiceButton:update()
    self:draw()
    if mouseButtonIsNotPressedDown and mouseIsHoveringOver(self) then
        if leftMouseButtonIsHeldDown() then
            mouseButtonIsNotPressedDown = false
            if self.onClick then self.onClick() end
        elseif rightMouseButtonIsHeldDown() then
            mouseButtonIsNotPressedDown = false
            if self.onRightClick then self.onRightClick() end
        end
    end
end

MidiTriggerButton = {}
MidiTriggerButton.__index = MidiTriggerButton

function MidiTriggerButton:new(x, y, size, onClick, getTooltip, onRightClick)
    local self = {}
    setmetatable(self, MidiTriggerButton)
    self.x = x
    self.y = y
    self.width = size
    self.height = size
    self.onClick = onClick
    self.getTooltip = getTooltip
    self.onRightClick = onRightClick
    return self
end

function MidiTriggerButton:draw()
    if mouseIsHoveringOver(self) or midiTriggerEnabled then
        setThemeColor("topButtonTextHover")
    else
        setThemeColor("topButtonText")
    end

    local cx = self.x + self.width / 2
    local cy = self.y + self.height / 2
    local r = self.width / 2.5
    
    gfx.circle(cx, cy, r, 0)
    
    local pinR = math.max(1, self.width / 15)
    
    gfx.circle(cx - r*0.6, cy + r*0.2, pinR, 1)
    gfx.circle(cx, cy + r*0.5, pinR, 1)
    gfx.circle(cx + r*0.6, cy + r*0.2, pinR, 1)
    
    if midiTriggerEnabled then
       gfx.circle(cx, cy, r*0.3, 1)
    end

    if tooltipsEnabled and mouseIsHoveringOver(self) and self.getTooltip then
        local tooltip = self.getTooltip()
        if tooltip then
            queueTooltip(tooltip, gfx.mouse_x, gfx.mouse_y)
        end
    end
end

function MidiTriggerButton:update()
    self:draw()
    if mouseButtonIsNotPressedDown and mouseIsHoveringOver(self) then
        if leftMouseButtonIsHeldDown() then
            mouseButtonIsNotPressedDown = false
            if self.onClick then self.onClick() end
        elseif rightMouseButtonIsHeldDown() then
            mouseButtonIsNotPressedDown = false
            if self.onRightClick then self.onRightClick() end
        end
    end
end

PinButton = {}
PinButton.__index = PinButton

function PinButton:new(x, y, size, onClick, getTooltip)
    local self = {}
    setmetatable(self, PinButton)
    self.x = x
    self.y = y
    self.width = size
    self.height = size
    self.onClick = onClick
    self.getTooltip = getTooltip
    return self
end

function PinButton:draw()
    local r = self.width / 2
    local cx = self.x + r
    local cy = self.y + r
    
    if mouseIsHoveringOver(self) or alwaysOnTopEnabled then
        setThemeColor("topButtonTextHover")
    else
        setThemeColor("topButtonText")
    end
    
    -- Border (Circle)
    gfx.circle(cx, cy, r, 0)
    
    -- Pin Icon
    -- Pin head
    local headR = r * 0.3
    gfx.circle(cx, cy - r*0.2, headR, 1)
    
    -- Pin body (line)
    gfx.line(cx, cy - r*0.2, cx, cy + r*0.4)
    
    -- Active indicator
    if alwaysOnTopEnabled then
       gfx.circle(cx + r*0.5, cy - r*0.5, r*0.2, 1)
    end

    if tooltipsEnabled and mouseIsHoveringOver(self) and self.getTooltip then
        local tooltip = self.getTooltip()
        if tooltip then
            queueTooltip(tooltip, gfx.mouse_x, gfx.mouse_y)
        end
    end
end

function PinButton:update()
    self:draw()
    if mouseButtonIsNotPressedDown and mouseIsHoveringOver(self) then
        if leftMouseButtonIsHeldDown() then
            mouseButtonIsNotPressedDown = false
            if self.onClick then self.onClick() end
        end
    end
end

local chordTextWidth = nil

function Interface:addBottomFrame()


	local xMargin = s(8)
	local yMargin = sy(8) + (self.keySelectionFrameHeight or sy(25)) + sy(6)
	local xPadding = sx(7)
	local yPadding = sy(30)
	local headerHeight = sy(25)
	local inversionLabelWidth = sx(80)
	local inversionValueBoxWidth = s(55)

	local chordButtonsFrameHeight = self.height - yMargin
	self:addFrame(xMargin+dockerXPadding, yMargin, self.width - 2 * xMargin, chordButtonsFrameHeight)
  
  self:addHoldButton(xMargin, yMargin, xPadding)
  self:addKillButton(xMargin, yMargin, xPadding)
  self:addStrumButton(xMargin, yMargin, xPadding)
  self:addArpButton(xMargin, yMargin, xPadding)
  self:addVoiceLeadingButton(xMargin, yMargin, xPadding)

  -- REPLACED "In Scale" Toggle with "Filter" Dropdown
  local extraSpacing = sx(15)
  local inScaleButtonX = topButtonXPos(xMargin, xPadding, 5) + extraSpacing
  local inScaleButtonY = topButtonYPos(yMargin)
  local buttonWidth = sx(120) -- Wider to fit "Jazz (All)"
  local buttonHeight = topButtonHeight()
  
  local filterOptions = {"Basic", "Standard", "Jazz", "Std (All)", "Jazz (All)"}
  
  -- Determine current index based on state
  local currentIndex = 2 -- Default Standard
  if chordVisibilityMode == 1 then currentIndex = 1
  elseif chordVisibilityMode == 2 then
      if showOnlyScaleChords then currentIndex = 2 else currentIndex = 4 end
  elseif chordVisibilityMode == 3 then
      if showOnlyScaleChords then currentIndex = 3 else currentIndex = 5 end
  end
  
  local onFilterSelect = function(index)
      if index == 1 then
          chordVisibilityMode = 1; showOnlyScaleChords = true
      elseif index == 2 then
          chordVisibilityMode = 2; showOnlyScaleChords = true
      elseif index == 3 then
          chordVisibilityMode = 3; showOnlyScaleChords = true
      elseif index == 4 then
          chordVisibilityMode = 2; showOnlyScaleChords = false
      elseif index == 5 then
          chordVisibilityMode = 3; showOnlyScaleChords = false
      end
      
      reaper.SetExtState("TK_ChordGun", "vocabMode", tostring(chordVisibilityMode), true)
      reaper.SetExtState("TK_ChordGun", "showOnlyScaleChords", showOnlyScaleChords and "1" or "0", true)
      chordListScrollOffset = 0
      updateScaleChords() -- Refresh lists
      guiShouldBeUpdated = true
  end
  
  self:addDropdown(inScaleButtonX+dockerXPadding, inScaleButtonY, buttonWidth, buttonHeight, filterOptions, currentIndex, onFilterSelect)

  local lenButtonX = topButtonXPos(xMargin, xPadding, 6) + extraSpacing + sx(15) + (buttonWidth - topButtonWidth())
  local lenButtonY = topButtonYPos(yMargin)
  self:addNoteLengthControl(lenButtonX, lenButtonY, {showLabel = false, buttonWidth = topButtonWidth()})

  
  self:addPianoKeyboard(xMargin, yMargin, xPadding, yPadding, headerHeight)
  self:addProgressionSlots(xMargin, yMargin, xPadding, yPadding, headerHeight)
  self:addProgressionControls(xMargin, yMargin, xPadding, yPadding, headerHeight)
  self:addChordTextLabel(xMargin, yMargin, xPadding, inversionLabelWidth, inversionValueBoxWidth)
  self:addInversionLabel(xMargin, yMargin, xPadding, inversionLabelWidth, inversionValueBoxWidth)
  self:addInversionValueBox(xMargin, yMargin, xPadding, inversionValueBoxWidth)
  
  self:addHeaders(xMargin, yMargin, xPadding, yPadding, headerHeight)
	self:addChordButtons(xMargin, yMargin, xPadding, yPadding, headerHeight)
end

function Interface:addChordTextLabel(xMargin, yMargin, xPadding, inversionLabelWidth, inversionValueBoxWidth)

  local getChordTextCallback = function() return getChordText() end
  local chordTextXpos = xMargin + xPadding
  local chordTextYpos = yMargin + sy(4)
  
  local contentRight = getTopFrameContentRight(xMargin)
  local spacing = s(6)
  local inversionLabelRightX = contentRight - inversionValueBoxWidth - spacing
  local inversionLabelLeftX = inversionLabelRightX - inversionLabelWidth
  
  chordTextWidth = inversionLabelLeftX - chordTextXpos - sx(6)
  local chordTextHeight = sy(24)
  self:addLabel(chordTextXpos+dockerXPadding, chordTextYpos, chordTextWidth, chordTextHeight, getChordTextCallback, {xOffset = sx(250), color = "3399FF"})
end

function Interface:addInversionLabel(xMargin, yMargin, xPadding, inversionLabelWidth, inversionValueBoxWidth)

  local inversionLabelText = "Inversion:"
  
  local contentRight = getTopFrameContentRight(xMargin)
  local spacing = s(13)
  local inversionLabelRightX = contentRight - inversionValueBoxWidth - spacing
  local inversionLabelXPos = inversionLabelRightX - inversionLabelWidth
  
  local inversionLabelYPos = yMargin + sy(4)
  local inversionLabelTextHeight = sy(24)

  self:addLabel(inversionLabelXPos+dockerXPadding, inversionLabelYPos, inversionLabelWidth, inversionLabelTextHeight, function() return inversionLabelText end, {align = "right"})
end

function Interface:addInversionValueBox(xMargin, yMargin, xPadding, inversionValueBoxWidth)

  local contentRight = getTopFrameContentRight(xMargin)
  local pickerLeftShift = s(8)
  local inversionValueBoxXPos = contentRight - inversionValueBoxWidth - pickerLeftShift
  
  local inversionValueBoxYPos = yMargin + sy(9)
  local inversionValueBoxHeight = sy(15)
  self:addChordInversionValueBox(inversionValueBoxXPos+dockerXPadding, inversionValueBoxYPos, inversionValueBoxWidth, inversionValueBoxHeight)
end

function Interface:addHeaders(xMargin, yMargin, xPadding, yPadding, headerHeight)
  
  local minColumns = 10
  local numColumns = math.max(minColumns, #scaleNotes)

  for i = 1, numColumns do

    local headerWidth = sx(104)
    local innerSpacing = sx(2)

    local headerXpos = xMargin+xPadding-sx(1) + headerWidth * (i-1) + innerSpacing * i
    local headerYpos = yMargin+yPadding
    
    local scaleIdx = i
    local textFunc = function() 
        if scaleIdx <= #scaleNotes then
            return getScaleDegreeHeader(scaleIdx) 
        else
            return "" 
        end
    end
    
    local columnIndex = (i <= #scaleNotes) and i or nil
    self:addHeader(headerXpos+dockerXPadding, headerYpos, headerWidth, headerHeight, textFunc, columnIndex)
  end
end

function Interface:addChordButtons(xMargin, yMargin, xPadding, yPadding, headerHeight)

  local numColumns = 10
  
  local scaleNoteIndex = 1
  local currentNote = getScaleTonicNote()

  for colIndex = 1, numColumns do

    if colIndex <= #scaleNotes then
        
        while not noteIsInScale(currentNote) do
            currentNote = currentNote + 1
        end

        for chordTypeIndex, chord in ipairs(scaleChords[scaleNoteIndex]) do

            local numberOfChordsInScale = getNumberOfScaleChordsForScaleNoteIndex(scaleNoteIndex)
            local chordIsInScale = chordTypeIndex <= numberOfChordsInScale

            if showOnlyScaleChords and not chordIsInScale then
                goto continue
            end

            local visualRowIndex = chordTypeIndex - chordListScrollOffset
            
            if visualRowIndex < 1 then 
                goto continue 
            end

            if visualRowIndex > maxVisibleRows then
                goto continue
            end

            local text = getScaleNoteName(scaleNoteIndex) .. chord['display']

            local buttonWidth = sx(104)
            local buttonHeight = sy(38)
            local innerSpacing = sx(2)
            
            local xPos = xMargin + xPadding + buttonWidth * (colIndex-1) + innerSpacing * colIndex + dockerXPadding
            local yPos = yMargin + yPadding + headerHeight + buttonHeight * (visualRowIndex-1) + innerSpacing * (visualRowIndex-1) - sy(3)
    
            if yPos + buttonHeight < self.height - sy(10) then
                self:addChordButton(text, xPos, yPos, buttonWidth, buttonHeight, scaleNoteIndex, chordTypeIndex, chordIsInScale)   	
            end

            ::continue::
        end
        
        scaleNoteIndex = scaleNoteIndex + 1
        currentNote = currentNote + 1
    else
        -- Draw empty placeholder buttons for grid consistency
        for row = 1, maxVisibleRows do
            local buttonWidth = sx(104)
            local buttonHeight = sy(38)
            local innerSpacing = sx(2)
            
            local xPos = xMargin + xPadding + buttonWidth * (colIndex-1) + innerSpacing * colIndex + dockerXPadding
            local yPos = yMargin + yPadding + headerHeight + buttonHeight * (row-1) + innerSpacing * (row-1) - sy(3)
            
            -- Add a disabled/empty button visual
            -- We use a dummy button that does nothing
            self:addSimpleButton("", xPos, yPos, buttonWidth, buttonHeight, function() end, nil, nil, true)
            
            -- Hack: Override the draw function of the last added element to make it look "empty"
            local btn = self.elements[#self.elements]
            btn.draw = function(self)
                setThemeColor("chordOutOfScale")
                gfx.rect(self.x, self.y, self.width, self.height, 1)
            end
        end
    end
  end
end
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/TK Scripts/Midi/TK_ChordGun"


--clearConsoleWindow()

interfaceWidth = getInterfaceWidth()
interfaceHeight = getInterfaceHeight()

updateScaleData()
loadMidiTriggerMappings()

local interface = Interface:init("TK ChordGun (Mod of ChordGun by Pandabot)")
interface:startGui()

local function windowHasNotBeenClosed()
	return inputCharacter ~= -1
end

local function cleanup()

    if gfx.w and gfx.h then
        setInterfaceWidth(gfx.w)
        setInterfaceHeight(gfx.h)
        
        local dockState, xpos, ypos = gfx.dock(-1, 0, 0, 0, 0)
        setInterfaceXPosition(xpos)
        setInterfaceYPosition(ypos)
        setDockState(dockState)
    end

	if fifthWheelWindowOpen then
		reaper.SetExtState("TK_ChordGun_FifthWheel", "forceClose", "1", false)
		fifthWheelWindowOpen = false
	end
	

	if helpWindowOpen then
		helpWindowOpen = false
		reaper.SetExtState("TK_ChordGun_Help", "closed", "0", false)
	end
end

local function main()

	if fifthWheelWindowOpen then
		local fifthClosed = reaper.GetExtState("TK_ChordGun_FifthWheel", "closed")
		if fifthClosed == "1" then
			fifthWheelWindowOpen = false
			reaper.SetExtState("TK_ChordGun_FifthWheel", "closed", "0", false)
		end
	end

	if helpWindowOpen then
		local helpClosed = reaper.GetExtState("TK_ChordGun_Help", "closed")
		if helpClosed == "1" then
			helpWindowOpen = false
			reaper.SetExtState("TK_ChordGun_Help", "closed", "0", false)
		end
	end

	if gfx.w ~= interface.lastWidth or gfx.h ~= interface.lastHeight then

		if reaper.GetExtState("TK_ChordGun", "useFixedRatio") ~= "0" then
			local dynWidth = getDynamicBaseWidth()
			local targetRatio = dynWidth / baseHeight
			local currentRatio = gfx.w / gfx.h
			

			if math.abs(currentRatio - targetRatio) > 0.01 then

				local newHeight = math.floor(gfx.w / targetRatio)
				if newHeight ~= gfx.h then
					gfx.init("", gfx.w, newHeight)
					gfx.h = newHeight
				end
			end
		end

		interface.lastWidth = gfx.w
		interface.lastHeight = gfx.h
		interface.width = gfx.w
		interface.height = gfx.h
		setInterfaceWidth(gfx.w)
		setInterfaceHeight(gfx.h)
		interface.elements = {}
		currentWidth = gfx.w
		dockerXPadding = getDockerXPadding()
		interface:addDocker()
		interface:addTopFrame()
		interface:addBottomFrame()
	end

	handleInput(interface)
	updateChordRecognition()
	checkFifthWheelUpdates()

	if windowHasNotBeenClosed() then
		reaper.runloop(main)
	else
		cleanup()
	end
	
	interface:update()
end

reaper.atexit(cleanup)
main()



