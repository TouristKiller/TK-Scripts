-- @description TK ChordGun - Enhanced chord generator with scale filter/remap and chord recognition
-- @author TouristKiller (based on pandabot ChordGun)
-- @version 2.1.3
-- @changelog
--[[
2.1.3
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
+ Two-level dropdown system: Scale System â†’ Scale Type
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

baseWidth = 775
baseHeight = 840


function getDynamicBaseWidth()
  local numScaleNotes = #scaleNotes
  if numScaleNotes <= 7 then
    return 775
  else

    local extraColumns = numScaleNotes - 7
    return 775 + (extraColumns * 112)
  end
end

local fontScale = tonumber(reaper.GetExtState("TK_ChordGun", "fontScale")) or 1.25

local function fontSize(value)
  return math.floor((s(value) * fontScale) + 0.5)
end

local function applyDefaultFont()

  local useMono = reaper.GetExtState("TK_ChordGun", "useMonospaceFont") == "1"

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

chords = {
  {
    name = 'major',
    code = 'major',
    display = '',
    pattern = '10001001'
  },
  {
    name = 'minor',
    code = 'minor',
    display = 'm',
    pattern = '10010001'
  },
  {
    name = 'power chord',
    code = 'power',
    display = '5',
    pattern = '10000001'
  },
  {
    name = 'suspended second',
    code = 'sus2',
    display = 'sus2',
    pattern = '10100001'
  },
  {
    name = 'suspended fourth',
    code = 'sus4',
    display = 'sus4',
    pattern = '10000101'
  },
  {
    name = 'diminished',
    code = 'dim',
    display = 'dim',
    pattern = '1001001'
  },  
  {
    name = 'augmented',
    code = 'aug',
    display = 'aug',
    pattern = '100010001'
  },
  {
    name = 'major sixth',
    code = 'maj6',
    display = '6',
    pattern = '1000100101'
  },
  {
    name = 'minor sixth',
    code = 'min6',
    display = 'm6',
    pattern = '1001000101'
  },
  {
    name = 'dominant seventh',
    code = '7',
    display = '7',
    pattern = '10001001001'
  },
  {
    name = 'major seventh',
    code = 'maj7',
    display = 'maj7',
    pattern = '100010010001'
  },
  {
    name = 'minor seventh',
    code = 'min7',
    display = 'm7',
    pattern = '10010001001'
  },
  {
    name = 'minor major seventh',
    code = 'minMaj7',
    display = 'm(maj7)',
    pattern = '100100010001'
  },
  {
    name = 'flat fifth',
    code = 'flat5',
    display = '5-',
    pattern = '10000010'
  },
}


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

function mouseIsHoveringOver(element)

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
	

	gfx.set(0.1, 0.1, 0.1, 0.95)
	gfx.rect(tooltipX, tooltipY, boxWidth, boxHeight, 1)
	

	gfx.set(1, 0.84, 0, 1)
	gfx.rect(tooltipX, tooltipY, boxWidth, boxHeight, 0)
	

	gfx.set(1, 1, 1, 1)
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


local workingDirectory = reaper.GetResourcePath() .. "/Scripts/ChordGun/src"

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
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/ChordGun/src"

local activeProjectIndex = 0
local sectionName = "com.pandabot.ChordGun"

local scaleTonicNoteKey = "scaleTonicNote"
local scaleTypeKey = "scaleType"
local scaleNotesTextKey = "scaleNotesText"
local chordTextKey = "chordText"
local chordInversionStatesKey = "chordInversionStates"
local selectedScaleNoteKey = "selectedScaleNote"
local octaveKey = "octave"
local selectedChordTypesKey = "selectedChordTypes"
local scaleNoteNamesKey = "scaleNoteNames"
local scaleDegreeHeadersKey = "scaleDegreeHeaders"
local notesThatArePlayingKey = "notesThatArePlaying"
local dockStateKey = "dockState"
local windowShouldBeDockedKey = "shouldBeDocked"
local interfaceXPositionKey = "interfaceXPosition"
local interfaceYPositionKey = "interfaceYPosition"
local interfaceWidthKey = "interfaceWidth"
local interfaceHeightKey = "interfaceHeight"
local noteLengthIndexKey = "noteLengthIndex"
local scaleFilterEnabledKey = "scaleFilterEnabled"

local function setValue(key, value)
  reaper.SetProjExtState(activeProjectIndex, sectionName, key, value)
end

local function getValue(key, defaultValue)

  local valueExists, value = reaper.GetProjExtState(activeProjectIndex, sectionName, key)

  if valueExists == 0 then
    setValue(key, defaultValue)
    return tostring(defaultValue)
  end

  return value
end


local strumEnabled = false
local strumDelayMs = 80
local bassMode = 0


local melodySettings = {
  density = 2,
  octave = 5,
  useScaleNotes = false
}


local tooltipsEnabled = false


local scaleFilterGmemBlock = "TKChordGunFilter"
local scaleFilterMode = tonumber(getValue("scaleFilterMode", "0")) or 0


local chordProgression = {}
local maxProgressionSlots = 8
local progressionPlaying = false
local currentProgressionIndex = 0
local currentProgressionRepeat = 0
local progressionBeatsPerChord = 1
local progressionLastBeatTime = 0
local selectedProgressionSlot = nil
local progressionLength = 8


local pruneInternalNoteEvents
local registerInternalNoteEvent
local consumeInternalNoteEvent
local isExternalDevice
local suppressExternalMidiUntil = 0

local function getTableFromString(arg)

  local output = {}

  for match in arg:gmatch("([^,%s]+)") do
    output[#output + 1] = match
  end

  return output
end

local globalExtSection = "TK_ChordGun"

local function setPersistentValue(key, value)
  if not reaper.SetExtState then return end
  reaper.SetExtState(globalExtSection, key, tostring(value), true)
end

local function getPersistentValue(key)
  if not reaper.GetExtState then return nil end
  local saved = reaper.GetExtState(globalExtSection, key)
  if saved ~= nil and saved ~= "" then
    return saved
  end
  return nil
end

local function getPersistentNumber(key, defaultValue)
  local globalValue = getPersistentValue(key)
  if globalValue ~= nil then
    return tonumber(globalValue)
  end
  return tonumber(getValue(key, defaultValue))
end

local function setPersistentNumber(key, value)
  setValue(key, value)
  setPersistentValue(key, value)
end

local function updateScaleFilterState()
  if not reaper.gmem_attach or not reaper.gmem_write then return end
  if not reaper.gmem_attach(scaleFilterGmemBlock) then return end
  reaper.gmem_write(0, scaleFilterMode)
  for i = 0, 11 do
    local noteIndex = i + 1
    local allowed = (scalePattern and scalePattern[noteIndex]) and 1 or 0
    reaper.gmem_write(1 + i, allowed)
  end
end

local function setScaleFilterMode(mode)
  scaleFilterMode = mode
  setValue("scaleFilterMode", tostring(mode))
  updateScaleFilterState()
end

local function cycleScaleFilterMode()
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

local function getScaleFilterModeText()
  if scaleFilterMode == 0 then return "Off"
  elseif scaleFilterMode == 1 then return "Filter"
  else return "Remap"
  end
end


local recognizedChord = ""
local chordInputNotes = {}
local lastInputIdx = nil

local function updateChordInputTracking()

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
  end
  table.sort(notes)
  return notes
end

local function analyzeChord(midiNotes)
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

local function getChordName(chordAnalysis)
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

local function updateChordRecognition()
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
  reaper.SetProjExtState(activeProjectIndex, sectionName, key, table.concat(value, ","))
end

local function getTableValue(key, defaultValue)

  local valueExists, value = reaper.GetProjExtState(activeProjectIndex, sectionName, key)

  if valueExists == 0 then
    setTableValue(key, defaultValue)
    return defaultValue
  end

  return getTableFromString(value)
end

--[[ ]]--

function getScaleTonicNote()
  return tonumber(getValue(scaleTonicNoteKey, defaultScaleTonicNoteValue))
end

function setScaleTonicNote(arg)
  setValue(scaleTonicNoteKey, arg)
end

--

function getScaleType()
  return tonumber(getValue(scaleTypeKey, defaultScaleTypeValue))
end

function setScaleType(arg)
  setValue(scaleTypeKey, arg)
end

--


function getScaleSystemIndex()
  local index = tonumber(reaper.GetExtState("TKChordGun", "scaleSystem"))
  if not index or index < 1 or index > #scaleSystems then
    return 1
  end
  return index
end

function setScaleSystemIndex(index)
  reaper.SetExtState("TKChordGun", "scaleSystem", tostring(index), true)
end

function getScaleWithinSystemIndex()
  local systemIndex = getScaleSystemIndex()
  local index = tonumber(reaper.GetExtState("TKChordGun", "scaleWithinSystem"))
  

  local system = scaleSystems[systemIndex]
  if not index or index < 1 or not system or index > #system.scales then
    return 1
  end
  return index
end

function setScaleWithinSystemIndex(index)
  reaper.SetExtState("TKChordGun", "scaleWithinSystem", tostring(index), true)
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
  return getValue(scaleNotesTextKey, defaultScaleNotesTextValue)
end

function setScaleNotesText(arg)
  setValue(scaleNotesTextKey, arg)
end

--

function getChordText()
  return getValue(chordTextKey, defaultChordTextValue)
end

function setChordText(arg)
  setValue(chordTextKey, arg)
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
  return tonumber(getValue(selectedScaleNoteKey, defaultSelectedScaleNote))
end

function setSelectedScaleNote(arg)
  setValue(selectedScaleNoteKey, arg)
end

--

function getOctave()
  return tonumber(getValue(octaveKey, defaultOctave))
end

function setOctave(arg)
  setValue(octaveKey, arg)
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

  return getTableValue(selectedChordTypesKey, defaultSelectedChordTypes)
end

function getSelectedChordType(index)

  local temp = getTableValue(selectedChordTypesKey, defaultSelectedChordTypes)
  return tonumber(temp[index])
end

function setSelectedChordType(index, arg)

  local temp = getSelectedChordTypes()
  temp[index] = arg
  setTableValue(selectedChordTypesKey, temp)
end

--

function getScaleNoteNames()
  return getTableValue(scaleNoteNamesKey, defaultScaleNoteNames)
end

function getScaleNoteName(index)
  local temp = getTableValue(scaleNoteNamesKey, defaultScaleNoteNames)
  return temp[index]
end

function setScaleNoteName(index, arg)

  local temp = getScaleNoteNames()
  temp[index] = arg
  setTableValue(scaleNoteNamesKey, temp)
end

--

function getScaleDegreeHeaders()
  return getTableValue(scaleDegreeHeadersKey, defaultScaleDegreeHeaders)
end

function getScaleDegreeHeader(index)
  local temp = getTableValue(scaleDegreeHeadersKey, defaultScaleDegreeHeaders)
  return temp[index]
end

function setScaleDegreeHeader(index, arg)

  local temp = getScaleDegreeHeaders()
  temp[index] = arg
  setTableValue(scaleDegreeHeadersKey, temp)
end

--

function getChordInversionStates()
  return getTableValue(chordInversionStatesKey, defaultInversionStates)
end

function getChordInversionState(index)

  local temp = getTableValue(chordInversionStatesKey, defaultInversionStates)
  local value = temp[index]
  if value == nil then
    return 0
  end
  return tonumber(value)
end

function setChordInversionState(index, arg)

  local temp = getChordInversionStates()
  temp[index] = arg
  setTableValue(chordInversionStatesKey, temp)
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
  return getTableValue(notesThatArePlayingKey, defaultNotesThatArePlaying)
end

function setNotesThatArePlaying(arg)
  setTableValue(notesThatArePlayingKey, arg)
end

--

function getDockState()
  return tonumber(getValue(dockStateKey, defaultDockState))
end

function setDockState(arg)
  setValue(dockStateKey, arg)
end

function windowShouldBeDocked()
  return getValue(windowShouldBeDockedKey, defaultWindowShouldBeDocked) == tostring(true)
end

function setWindowShouldBeDocked(arg)
  setValue(windowShouldBeDockedKey, tostring(arg))
end

function getInterfaceXPosition()
  return tonumber(getValue(interfaceXPositionKey, defaultInterfaceXPosition()))
end

function setInterfaceXPosition(arg)
  setValue(interfaceXPositionKey, arg)
end

function getInterfaceYPosition()
  return tonumber(getValue(interfaceYPositionKey, defaultInterfaceYPosition()))
end

function setInterfaceYPosition(arg)
  setValue(interfaceYPositionKey, arg)
end

function getInterfaceWidth()
  return getPersistentNumber(interfaceWidthKey, baseWidth * defaultUiScale)
end

function setInterfaceWidth(arg)
  setPersistentNumber(interfaceWidthKey, arg)
end

function getInterfaceHeight()
  return getPersistentNumber(interfaceHeightKey, baseHeight * defaultUiScale)
end

function setInterfaceHeight(arg)
  setPersistentNumber(interfaceHeightKey, arg)
end


local noteLengthOptions = {
  {label = "Grid", qn = nil},
  {label = "1/32", qn = 0.125},
  {label = "1/16", qn = 0.25},
  {label = "1/8",  qn = 0.5},
  {label = "1/4",  qn = 1.0},
  {label = "1/2",  qn = 2.0},
  {label = "1 bar", qn = 4.0}
}
local noteLengthLabels = {}
for i, option in ipairs(noteLengthOptions) do
  noteLengthLabels[i] = option.label
end
local defaultNoteLengthIndex = 1

function getNoteLengthIndex()
  local index = getPersistentNumber(noteLengthIndexKey, defaultNoteLengthIndex) or defaultNoteLengthIndex
  if index < 1 then index = 1 end
  if index > #noteLengthOptions then index = #noteLengthOptions end
  return math.floor(index)
end

function setNoteLengthIndex(index)
  setPersistentNumber(noteLengthIndexKey, index)
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
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/ChordGun/src"

mouseButtonIsNotPressedDown = true

currentWidth = 0

scaleTonicNote = getScaleTonicNote()
scaleType = getScaleType()

guiShouldBeUpdated = false


scaleSystems = {
  {
    name = "Diatonic",
    scales = {
      { name = "Major", pattern = "101011010101", 
        description = "Heptatonic (7 notes) - Bright, happy sound\nMost common scale in Western music" },
      { name = "Natural Minor", pattern = "101101011010",
        description = "Heptatonic (7 notes) - Dark, sad sound\nRelative minor of Major scale" },
      { name = "Harmonic Minor", pattern = "101101011001",
        description = "Heptatonic (7 notes) - Exotic, dramatic\nRaised 7th creates leading tone" },
      { name = "Melodic Minor", pattern = "101101010101",
        description = "Heptatonic (7 notes) - Jazz favorite\nRaised 6th and 7th ascending" },
      { name = "Ionian", pattern = "101011010101",
        description = "Heptatonic (7 notes) - Same as Major\n1st mode of major scale" },
      { name = "Aeolian", pattern = "101101011010",
        description = "Heptatonic (7 notes) - Same as Natural Minor\n6th mode of major scale" },
      { name = "Dorian", pattern = "101101010110",
        description = "Heptatonic (7 notes) - Jazzy, sophisticated\n2nd mode - minor with raised 6th" },
      { name = "Mixolydian", pattern = "101011010110",
        description = "Heptatonic (7 notes) - Bluesy, rock\n5th mode - major with flat 7th" },
      { name = "Phrygian", pattern = "110101011010",
        description = "Heptatonic (7 notes) - Spanish, flamenco\n3rd mode - minor with flat 2nd" },
      { name = "Lydian", pattern = "101010110101",
        description = "Heptatonic (7 notes) - Dreamy, floating\n4th mode - major with sharp 4th" },
      { name = "Locrian", pattern = "110101101010",
        description = "Heptatonic (7 notes) - Unstable, dissonant\n7th mode - diminished quality" }
    }
  },
  {
    name = "Pentatonic",
    scales = {
      { name = "Major Pentatonic", pattern = "101010010100",
        description = "Pentatonic (5 notes) - Bright, happy\nC-D-E-G-A | Universal in folk music" },
      { name = "Minor Pentatonic", pattern = "100101010010",
        description = "Pentatonic (5 notes) - Rock/blues basis\nC-Eb-F-G-Bb | Most common in rock" },
      { name = "Blues Scale", pattern = "100101110010",
        description = "Hexatonic (6 notes) - Blues/rock\nC-Eb-F-F#-G-Bb | Minor pentatonic + blue note" },
      { name = "Egyptian/Suspended", pattern = "101001010010",
        description = "Pentatonic (5 notes) - Mysterious, suspended\nC-D-F-G-Bb | Ancient Egyptian music" },
      { name = "Japanese (In Sen)", pattern = "110001010010",
        description = "Pentatonic (5 notes) - Traditional Japanese\nC-Db-F-G-Bb | Meditative, contemplative" },
      { name = "Hirajoshi", pattern = "101100010010",
        description = "Pentatonic (5 notes) - Japanese, serene\nC-D-Eb-G-Ab | Tranquil, peaceful" }
    }
  },
  {
    name = "Messiaen",
    scales = {

      { name = "Mode 1", pattern = "101010101010", isCustom = true, intervals = "2-2-2-2-2-2",
        description = "Hexatonic (6 notes) - Whole Tone Scale\nDreamy, floating, ambiguous | Debussy's favorite\nSymmetrical: divides octave into 6 equal parts" },
      

      { name = "Mode 2.1", pattern = "110110110110", isCustom = true, intervals = "1-2-1-2-1-2-1-2",
        description = "Octatonic (8 notes) - Half-Whole Diminished\nJazz/classical favorite | Rich chord possibilities\nAlternates half and whole steps (1st transposition)" },
      { name = "Mode 2.2", pattern = "101101101101", isCustom = true, intervals = "2-1-2-1-2-1-2-1",
        description = "Octatonic (8 notes) - Whole-Half Diminished\nAlternates whole and half steps (2nd transposition)\nUsed extensively in bebop and modern jazz" },
      { name = "Mode 2.3", pattern = "011011011011", isCustom = true, intervals = "1-2-1-2-1-2-1-2",
        description = "Octatonic (8 notes) - Half-Whole Diminished\n3rd and final transposition of Mode 2\nSymmetrical: repeats every minor 3rd" },
      

      { name = "Mode 3.1", pattern = "101110110111", isCustom = true, intervals = "2-1-1-2-1-1-2-1-1",
        description = "Nonatonic (9 notes) - Dense, chromatic\nRepeating 2-1-1 pattern | Very colorful\n1st transposition of 4 possible" },
      { name = "Mode 3.2", pattern = "110111011011", isCustom = true, intervals = "1-1-2-1-1-2-1-1-2",
        description = "Nonatonic (9 notes) - Dense, chromatic\nRepeating 1-1-2 pattern | 2nd transposition\nUsed in Messiaen's 'Quartet for the End of Time'" },
      { name = "Mode 3.3", pattern = "011101110111", isCustom = true, intervals = "1-2-1-1-2-1-1-2-1",
        description = "Nonatonic (9 notes) - Dense, chromatic\n3rd transposition | Highly symmetrical\nContains many augmented and diminished chords" },
      { name = "Mode 3.4", pattern = "101101110111", isCustom = true, intervals = "2-1-1-2-1-1-2-1-1",
        description = "Nonatonic (9 notes) - Dense, chromatic\n4th and final transposition of Mode 3\nRich harmonic palette for composition" },
      

      { name = "Mode 4.1", pattern = "110001110001", isCustom = true, intervals = "1-1-3-1-1-1-3-1",
        description = "Octatonic (8 notes) - Exotic, Eastern flavor\nRepeating 1-1-3-1 pattern | 1st transposition\nUsed for mysterious, otherworldly sounds" },
      { name = "Mode 4.2", pattern = "100011100011", isCustom = true, intervals = "1-3-1-1-1-3-1-1",
        description = "Octatonic (8 notes) - Exotic, Eastern flavor\n2nd transposition | Alternating small/large gaps\nPopular in film scores" },
      { name = "Mode 4.3", pattern = "000111000111", isCustom = true, intervals = "3-1-1-1-3-1-1-1",
        description = "Octatonic (8 notes) - Exotic, Eastern flavor\n3rd transposition | Creates tension and release\nContains augmented and minor triads" },
      { name = "Mode 4.4", pattern = "001110001110", isCustom = true, intervals = "1-1-1-3-1-1-1-3",
        description = "Octatonic (8 notes) - Exotic, Eastern flavor\n4th transposition | Clusters and wide leaps\nUseful for dramatic moments" },
      { name = "Mode 4.5", pattern = "011100011100", isCustom = true, intervals = "1-1-3-1-1-1-3-1",
        description = "Octatonic (8 notes) - Exotic, Eastern flavor\n5th transposition | Repeating pattern\nSymmetrical structure" },
      { name = "Mode 4.6", pattern = "111000111000", isCustom = true, intervals = "1-1-3-1-1-1-3-1",
        description = "Octatonic (8 notes) - Exotic, Eastern flavor\n6th and final transposition of Mode 4\nComplete the symmetrical cycle" },
      

      { name = "Mode 5.1", pattern = "110001000011", isCustom = true, intervals = "1-4-1-1-4-1",
        description = "Hexatonic (6 notes) - Wide intervals, sparse\nRepeating 1-4-1 pattern | 1st transposition\nOpen, spacious sound with dramatic leaps" },
      { name = "Mode 5.2", pattern = "100010000111", isCustom = true, intervals = "4-1-1-4-1-1",
        description = "Hexatonic (6 notes) - Wide intervals, sparse\n2nd transposition | Major 3rd leaps\nUsed for ethereal, floating textures" },
      { name = "Mode 5.3", pattern = "000100011100", isCustom = true, intervals = "1-1-4-1-1-4",
        description = "Hexatonic (6 notes) - Wide intervals, sparse\n3rd transposition | Alternating gaps\nCreates sense of space and distance" },
      { name = "Mode 5.4", pattern = "001000111000", isCustom = true, intervals = "1-4-1-1-4-1",
        description = "Hexatonic (6 notes) - Wide intervals, sparse\n4th transposition | Pentatonic-like\nUseful for minimalist compositions" },
      { name = "Mode 5.5", pattern = "010001110001", isCustom = true, intervals = "4-1-1-4-1-1",
        description = "Hexatonic (6 notes) - Wide intervals, sparse\n5th transposition | Symmetrical gaps\nCreates mysterious atmosphere" },
      { name = "Mode 5.6", pattern = "100011100010", isCustom = true, intervals = "1-1-4-1-1-4",
        description = "Hexatonic (6 notes) - Wide intervals, sparse\n6th and final transposition of Mode 5\nCompletes the hexatonic cycle" },
      

      { name = "Mode 6.1", pattern = "101011010110", isCustom = true, intervals = "2-2-1-1-2-2-1-1",
        description = "Octatonic (8 notes) - Balanced, versatile\nRepeating 2-2-1-1 pattern | 1st transposition\nBlends whole tone and chromatic elements" },
      { name = "Mode 6.2", pattern = "010110101101", isCustom = true, intervals = "2-1-1-2-2-1-1-2",
        description = "Octatonic (8 notes) - Balanced, versatile\n2nd transposition | Smooth motion\nUseful for melodic lines" },
      { name = "Mode 6.3", pattern = "101101011011", isCustom = true, intervals = "1-1-2-2-1-1-2-2",
        description = "Octatonic (8 notes) - Balanced, versatile\n3rd transposition | Paired intervals\nCreates interesting harmonic progressions" },
      { name = "Mode 6.4", pattern = "011010110110", isCustom = true, intervals = "1-2-2-1-1-2-2-1",
        description = "Octatonic (8 notes) - Balanced, versatile\n4th transposition | Alternating pairs\nGood for both melody and harmony" },
      { name = "Mode 6.5", pattern = "110101101011", isCustom = true, intervals = "2-1-1-2-2-1-1-2",
        description = "Octatonic (8 notes) - Balanced, versatile\n5th transposition | Symmetrical structure\nUsed in Messiaen's piano works" },
      { name = "Mode 6.6", pattern = "101011011010", isCustom = true, intervals = "1-2-2-1-1-2-2-1",
        description = "Octatonic (8 notes) - Balanced, versatile\n6th and final transposition of Mode 6\nCompletes the octave division" },
      

      { name = "Mode 7.1", pattern = "111011110110", isCustom = true, intervals = "1-1-1-2-1-1-1-1-2-1",
        description = "Decatonic (10 notes) - Most chromatic\nRepeating 1-1-1-2-1 pattern | 1st transposition\nAlmost all 12 chromatic notes - highly dissonant" },
      { name = "Mode 7.2", pattern = "110111101101", isCustom = true, intervals = "1-1-2-1-1-1-1-2-1-1",
        description = "Decatonic (10 notes) - Most chromatic\n2nd transposition | Dense clusters\nUsed for intense, dramatic moments" },
      { name = "Mode 7.3", pattern = "101111011011", isCustom = true, intervals = "1-2-1-1-1-1-2-1-1-1",
        description = "Decatonic (10 notes) - Most chromatic\n3rd transposition | Maximum color\nMessiaen's most complex mode" },
      { name = "Mode 7.4", pattern = "011110110111", isCustom = true, intervals = "2-1-1-1-1-2-1-1-1-1",
        description = "Decatonic (10 notes) - Most chromatic\n4th transposition | Chromatic saturation\nUseful for avant-garde compositions" },
      { name = "Mode 7.5", pattern = "111101101110", isCustom = true, intervals = "1-1-1-1-2-1-1-1-2-1",
        description = "Decatonic (10 notes) - Most chromatic\n5th transposition | Dense harmony\nContains nearly every possible chord type" },
      { name = "Mode 7.6", pattern = "111011011101", isCustom = true, intervals = "1-1-2-1-1-1-2-1-1-1",
        description = "Decatonic (10 notes) - Most chromatic\n6th and final transposition of Mode 7\nCompletes Messiaen's modal system" }
    }
  },
  {
    name = "Jazz",
    scales = {
      { name = "Bebop Dominant", pattern = "10101101010110", isCustom = true, intervals = "2-2-1-2-2-1-1-1",
        description = "Octatonic (8 notes) - Classic bebop sound\nMixolydian + major 7th passing tone\nPerfect for dominant 7th chord lines" },
      { name = "Bebop Major", pattern = "10110101010110", isCustom = true, intervals = "2-2-1-2-1-1-2-1",
        description = "Octatonic (8 notes) - Major with chromatic\nMajor scale + #5 passing tone\nSmooth bebop melodies over major chords" },
      { name = "Bebop Minor", pattern = "10110101011010", isCustom = true, intervals = "2-1-2-2-1-1-2-1",
        description = "Octatonic (8 notes) - Minor with chromatic\nDorian + major 3rd passing tone\nUsed extensively in bebop improvisation" },
      { name = "Bebop Dorian", pattern = "10110101101010", isCustom = true, intervals = "2-1-2-2-2-1-1-2",
        description = "Octatonic (8 notes) - Dorian with passing tone\nDorian + major 3rd chromatic\nMiles Davis and John Coltrane favorite" },
      { name = "Altered Scale", pattern = "11010101010110", isCustom = true, intervals = "1-2-1-2-2-2-2",
        description = "Heptatonic (7 notes) - Super Locrian\n7th mode of melodic minor | All altered tensions\nDominant 7 with b9, #9, #11, b13" },
      { name = "Lydian Dominant", pattern = "10110110101010", isCustom = true, intervals = "2-2-2-1-2-1-2",
        description = "Heptatonic (7 notes) - Acoustic/Overtone scale\n4th mode of melodic minor | #11 with b7\nBartÃ³k, Debussy, modern jazz standard" },
      { name = "Harmonic Major", pattern = "10110101100110", isCustom = true, intervals = "2-2-1-2-1-3-1",
        description = "Heptatonic (7 notes) - Major with b6\nMajor scale with flattened 6th\nExotic sound, used in jazz and metal" },
      { name = "Melodic Minor", pattern = "10110101101010", isCustom = true, intervals = "2-1-2-2-2-2-1",
        description = "Heptatonic (7 notes) - Jazz minor\nNatural minor with raised 6 and 7\nFoundation of modern jazz harmony" },
      { name = "Whole Half Dim", pattern = "101101101101", isCustom = true, intervals = "2-1-2-1-2-1-2-1",
        description = "Octatonic (8 notes) - Symmetrical diminished\nAlternates whole and half steps\nDiminished 7th and dominant 7b9 chords" },
      { name = "Half Whole Dim", pattern = "110110110110", isCustom = true, intervals = "1-2-1-2-1-2-1-2",
        description = "Octatonic (8 notes) - Symmetrical diminished\nAlternates half and whole steps\nDiminished chords and diminished lines" }
    }
  },
  {
    name = "World Music",
    scales = {
      { name = "Hijaz", pattern = "11001101010", isCustom = true, intervals = "1-3-1-2-1-2-2",
        description = "Heptatonic (7 notes) - Arabic Maqam\nDramatic augmented 2nd interval | Middle Eastern flavor\nUsed in Arabic, Turkish, Greek, and Klezmer music" },
      { name = "Phrygian Dominant", pattern = "11001101010", isCustom = true, intervals = "1-3-1-2-1-2-2",
        description = "Heptatonic (7 notes) - Spanish/Flamenco\nPhrygian with major 3rd | Hijaz/Freygish mode\nEssential for flamenco, metal, and film scores" },
      { name = "Hungarian Minor", pattern = "10110011010", isCustom = true, intervals = "2-1-3-1-1-3-1",
        description = "Heptatonic (7 notes) - Gypsy/Hungarian\nMinor with raised 4th | Dramatic augmented intervals\nLiszt, Brahms, and Eastern European folk" },
      { name = "Double Harmonic", pattern = "11001100110", isCustom = true, intervals = "1-3-1-2-1-3-1",
        description = "Heptatonic (7 notes) - Byzantine/Arabic\nTwo augmented 2nds | Extremely exotic\nMiddle Eastern, Indian classical, and progressive metal" },
      { name = "Japanese Hirajoshi", pattern = "100101000101", isCustom = true, intervals = "2-1-4-1-4",
        description = "Pentatonic (5 notes) - Traditional Japanese\nSpacious, contemplative | Ancient court music\nUsed in koto, shakuhachi, and ambient music" },
      { name = "Japanese In Sen", pattern = "110010000110", isCustom = true, intervals = "1-4-2-1-4",
        description = "Pentatonic (5 notes) - Japanese Shakuhachi\nMinor pentatonic variant | Melancholic\nTraditional Zen Buddhist meditation music" },
      { name = "Japanese Iwato", pattern = "110001001001", isCustom = true, intervals = "1-4-1-4-2",
        description = "Pentatonic (5 notes) - Traditional Japanese\nDark, mysterious | Ancient court music\nUsed for dramatic and suspenseful scenes" },
      { name = "Bhairav (Raga)", pattern = "11001101001", isCustom = true, intervals = "1-3-1-2-1-3-2",
        description = "Heptatonic (7 notes) - North Indian Raga\nDawn raga | Peaceful yet serious mood\nClassical Indian music, meditative and devotional" },
      { name = "Kafi (Raga)", pattern = "10101011010", isCustom = true, intervals = "2-2-1-2-2-1-2",
        description = "Heptatonic (7 notes) - North Indian Raga\nDorian-like | Romantic, longing emotion\nPopular in folk and light classical music" },
      { name = "Spanish 8-Tone", pattern = "11010110110", isCustom = true, intervals = "1-2-1-1-2-1-2-2",
        description = "Octatonic (8 notes) - Flamenco composite\nCombines Phrygian and altered tones\nModern flamenco and fusion guitar" },
      { name = "Persian", pattern = "11001100110", isCustom = true, intervals = "1-3-1-2-1-3-1",
        description = "Heptatonic (7 notes) - Persian/Iranian\nSimilar to Double Harmonic | Rich ornaments\nTraditional Persian classical and Sufi music" },
      { name = "Enigmatic", pattern = "11001011001", isCustom = true, intervals = "1-3-2-2-2-1-1",
        description = "Heptatonic (7 notes) - Verdi's scale\nMysterious, unusual intervals | Experimental\nRare scale used by Giuseppe Verdi" }
    }
  },
  {
    name = "Blues & Soul",
    scales = {
      { name = "Blues Scale", pattern = "100110010010", isCustom = true, intervals = "3-2-1-1-3-2",
        description = "Hexatonic (6 notes) - Classic blues sound\nMinor pentatonic + blue note (b5)\nFoundation of blues, rock, and jazz" },
      { name = "Blues Major", pattern = "101101010010", isCustom = true, intervals = "2-1-1-2-2-2-2",
        description = "Heptatonic (7 notes) - Major blues flavor\nMajor pentatonic + blue notes\nCountry, blues-rock, and Southern rock" },
      { name = "Blues Minor", pattern = "100110110010", isCustom = true, intervals = "3-2-1-1-2-3",
        description = "Hexatonic (6 notes) - Minor blues variant\nMinor pentatonic + major 3rd\nChicago blues and blues-rock" },
      { name = "Mixo-Blues", pattern = "10110101011010", isCustom = true, intervals = "2-2-1-2-1-1-2-1",
        description = "Octatonic (8 notes) - Jazz-blues hybrid\nMixolydian + blue notes (#9, #11)\nJazz-blues, funk, and fusion" },
      { name = "Gospel Minor", pattern = "100111010010", isCustom = true, intervals = "3-2-1-2-2-2",
        description = "Hexatonic (6 notes) - Soulful, churchy\nMinor with raised 6th | Emotional\nGospel, R&B, and soul music" },
      { name = "Gospel Major", pattern = "101010110010", isCustom = true, intervals = "2-2-2-1-1-2-2",
        description = "Heptatonic (7 notes) - Uplifting, joyful\nMajor with chromatic passing tones\nGospel choir, worship music" },
      { name = "Dominant Blues", pattern = "10101101010010", isCustom = true, intervals = "2-2-1-2-2-1-2-2",
        description = "Octatonic (8 notes) - Dominant 7th blues\nMixolydian + blue note\nTexas blues, rockabilly, and swing" },
      { name = "Soul", pattern = "10110101010010", isCustom = true, intervals = "2-1-2-2-2-2-1-2",
        description = "Octatonic (8 notes) - Smooth R&B sound\nMajor + chromatic approach notes\nMotown, 70s soul, neo-soul" }
    }
  },
  {
    name = "Rock & Metal",
    scales = {
      { name = "Harmonic Minor", pattern = "10110100110", isCustom = true, intervals = "2-1-2-2-1-3-1",
        description = "Heptatonic (7 notes) - Classical/metal favorite\nNatural minor + major 7th | Dramatic\nNeoclassical metal, Yngwie Malmsteen, classical" },
      { name = "Phrygian Dominant", pattern = "11001101010", isCustom = true, intervals = "1-3-1-2-1-2-2",
        description = "Heptatonic (7 notes) - Metal staple\n5th mode of Harmonic Minor | Spanish/Egyptian\nMetallica, Slayer, progressive metal" },
      { name = "Neapolitan Minor", pattern = "11010100110", isCustom = true, intervals = "1-2-2-2-1-3-1",
        description = "Heptatonic (7 notes) - Dark, exotic minor\nMinor with flattened 2nd | Dramatic\nSymphonic metal, film scores" },
      { name = "Neapolitan Major", pattern = "11010110010", isCustom = true, intervals = "1-2-2-2-2-2-1",
        description = "Heptatonic (7 notes) - Bright yet exotic\nMajor with flattened 2nd | Unusual\nProgressive rock/metal, experimental" },
      { name = "Hungarian Major", pattern = "10011011010", isCustom = true, intervals = "3-1-2-1-2-1-2",
        description = "Heptatonic (7 notes) - Exotic major sound\nLydian with flat 6 and 7 | Augmented 2nd\nGypsy-flavored rock, folk metal" },
      { name = "Lydian #2", pattern = "11101101010", isCustom = true, intervals = "1-2-2-2-1-2-2",
        description = "Heptatonic (7 notes) - Bright and angular\nLydian with raised 2nd | Modern sound\nProgressive metal, math rock" },
      { name = "Super Locrian", pattern = "11010101010", isCustom = true, intervals = "1-2-1-2-2-2-2",
        description = "Heptatonic (7 notes) - Altered/diminished\n7th mode of melodic minor | Dissonant\nExtreme metal, technical death metal" },
      { name = "Aeolian b5", pattern = "10110010110", isCustom = true, intervals = "2-1-2-1-2-2-2",
        description = "Heptatonic (7 notes) - Half-diminished sound\nNatural minor with flat 5 | Dark\nDoom metal, atmospheric metal" }
    }
  }
}


scales = {}
for _, system in ipairs(scaleSystems) do
  for _, scale in ipairs(system.scales) do
    table.insert(scales, scale)
  end
end

local workingDirectory = reaper.GetResourcePath() .. "/Scripts/ChordGun/src"

notes = { 'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B' };
flatNotes = { 'C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B' };

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
  
  for chordIndex, chord in ipairs(chords) do
  
    if chordIsInScale(rootNote, chordIndex) then
      chordCount = chordCount + 1
      scaleChordsForRootNote[chordCount] = chord   
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
           
    if chordIsNotAlreadyIncluded(scaleChordsForRootNote, chord.code) then
      chordCount = chordCount + 1
      scaleChordsForRootNote[chordCount] = chord
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
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/ChordGun/src"

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
  local startPositionPPQ = reaper.MIDI_GetPPQPosFromProjTime(take, startPosition)
  local endPositionPPQ = reaper.MIDI_GetPPQPosFromProjTime(take, startPosition+gridUnitLength())
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
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/ChordGun/src"

function playMidiNote(midiNote)

  local virtualKeyboardMode = 0
  local channel = getCurrentNoteChannel()
  local noteOnCommand = 0x90 + channel
  local velocity = getCurrentVelocity()

  reaper.StuffMIDIMessage(virtualKeyboardMode, noteOnCommand, midiNote, velocity)
  registerInternalNoteEvent(midiNote, true)
end

function stopAllNotesFromPlaying()

  for midiNote = 0, 127 do

    local virtualKeyboardMode = 0
    local channel = getCurrentNoteChannel()
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
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/ChordGun/src"

function applyInversion(chord)
  
  local chordLength = #chord

  local selectedScaleNote = getSelectedScaleNote()
  local chordInversionValue = getChordInversionState(selectedScaleNote)
  

  local chord_ = {}
  for i, v in ipairs(chord) do
    chord_[i] = v
  end
  
  local oct = 0  
  
  if chordInversionValue < 0 then
    oct = math.floor(chordInversionValue / chordLength)
    chordInversionValue = chordInversionValue + (math.abs(oct) * chordLength)
  end
  
  for i = 1, chordInversionValue do
    local r = table.remove(chord_, 1)
    r = r + 12
    table.insert(chord_, #chord_ + 1, r )
  end
    
  for i = 1, #chord_ do
    chord_[i] = chord_[i] + (oct * 12)
  end

  return chord_
end

function getChordNotesArray(root, chord, octave)

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
  
  chordNotesArray = applyInversion(chordNotesArray)
  

  if bassMode > 0 then


    local bassNote = root + ((octave + 1 - bassMode) * 12) - 1
    

    table.insert(chordNotesArray, 1, bassNote)
  end
  
  return chordNotesArray
end
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/ChordGun/src"

function insertMidiNote(note, keepNotesSelected, selectedChord, noteIndex)

	local startPosition = getCursorPositionPPQ()
	

	if strumEnabled then
		local ppq = reaper.MIDI_GetPPQPosFromProjQN(activeTake(), 0)
		local quarterNote = reaper.MIDI_GetProjQNFromPPQPos(activeTake(), ppq + 1)
		local oneBeatInPPQ = (ppq + 1) - ppq
		local strumOffsetPPQ = (strumDelayMs / 1000.0) * (oneBeatInPPQ * 2)
		startPosition = startPosition + ((noteIndex - 1) * strumOffsetPPQ)
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
		end
		
	else
		endPosition = getMidiEndPositionPPQ()
		

		if strumEnabled then
			local ppq = reaper.MIDI_GetPPQPosFromProjQN(activeTake(), 0)
			local oneBeatInPPQ = (ppq + 1) - ppq
			local strumOffsetPPQ = (strumDelayMs / 1000.0) * (oneBeatInPPQ * 2)
			endPosition = endPosition + ((noteIndex - 1) * strumOffsetPPQ)
		end
		
		velocity = getCurrentVelocity()
		channel = getCurrentNoteChannel()
		muteState = false
	end

	local noSort = false

	reaper.MIDI_InsertNote(activeTake(), keepNotesSelected, muteState, startPosition, endPosition, channel, note, velocity, noSort)
end
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/ChordGun/src"

local function playScaleChord(chordNotesArray)

  stopNotesFromPlaying()
  
  if strumEnabled then

    local delaySeconds = strumDelayMs / 1000.0
    
    for noteIndex = 1, #chordNotesArray do
      playMidiNote(chordNotesArray[noteIndex])
      

      if noteIndex < #chordNotesArray then
        local startTime = reaper.time_precise()
        local targetTime = startTime + delaySeconds
        

        while reaper.time_precise() < targetTime do

        end
      end
    end
  else

    for noteIndex = 1, #chordNotesArray do
      playMidiNote(chordNotesArray[noteIndex])
    end
  end

  setNotesThatArePlaying(chordNotesArray) 
end


function addChordToProgression(scaleNoteIndex, chordTypeIndex, chordText, targetSlotOverride)
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
    chordProgression[targetSlot] = {
      scaleNoteIndex = scaleNoteIndex,
      chordTypeIndex = chordTypeIndex,
      text = chordText,
      beats = 1,
      repeats = 1
    }
  end
end

function playChordFromSlot(slotIndex)

  local slot = chordProgression[slotIndex]
  if not slot then return end
  

  stopAllNotesFromPlaying()
  

  local root = scaleNotes[slot.scaleNoteIndex]
  local chordData = scaleChords[slot.scaleNoteIndex][slot.chordTypeIndex]
  local octave = getOctave()
  local notes = getChordNotesArray(root, chordData, octave)
  

  for noteIndex, note in ipairs(notes) do
    if strumEnabled then

      local strumDelaySeconds = (strumDelayMs / 1000.0) * (noteIndex - 1)
      reaper.defer(function()
        playMidiNote(note)
      end)
    else

      playMidiNote(note)
    end
  end
  

  reaper.defer(function()
    local function stopNotes()
      for _, note in ipairs(notes) do
        stopNoteFromPlaying(note)
      end
    end
    

    local startTime = reaper.time_precise()
    local function waitAndStop()
      if reaper.time_precise() - startTime >= 0.5 then
        stopNotes()
      else
        reaper.defer(waitAndStop)
      end
    end
    waitAndStop()
  end)
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

  reaper.Undo_BeginBlock()
  

  local track = reaper.GetSelectedTrack(0, 0)
  
  if not track then
    local numTracks = reaper.CountTracks(0)
    reaper.InsertTrackAtIndex(numTracks, true)
    track = reaper.GetTrack(0, numTracks)
    reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "Melody", true)
    

    reaper.Main_OnCommand(40297, 0)
    reaper.SetTrackSelected(track, true)
    reaper.Main_OnCommand(40000, 0)
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
  local take = reaper.GetActiveTake(item)
  
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
      local octave = getOctave()
      local notes = getChordNotesArray(root, chordData, octave)
      
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
      file:write(slot.scaleNoteIndex .. "," .. slot.chordTypeIndex .. "," .. slot.text .. "," .. slot.beats .. "," .. slot.repeats .. "\n")
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

      local scaleNoteIndex, chordTypeIndex, text, beats, repeats = line:match("(%d+),(%d+),([^,]+),(%d+),(%d+)")
      if scaleNoteIndex then
        chordProgression[slotIndex] = {
          scaleNoteIndex = tonumber(scaleNoteIndex),
          chordTypeIndex = tonumber(chordTypeIndex),
          text = text,
          beats = tonumber(beats),
          repeats = tonumber(repeats)
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

function playProgressionChord(index)
  if index < 1 or index > #chordProgression then return end
  
  local chord = chordProgression[index]
  setSelectedScaleNote(chord.scaleNoteIndex)
  setSelectedChordType(chord.scaleNoteIndex, chord.chordTypeIndex)
  
  local root = scaleNotes[chord.scaleNoteIndex]
  local chordData = scaleChords[chord.scaleNoteIndex][chord.chordTypeIndex]
  local octave = getOctave()
  
  local chordNotesArray = getChordNotesArray(root, chordData, octave)
  

  for noteIndex = 1, #chordNotesArray do
    playMidiNote(chordNotesArray[noteIndex])
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
      if chord then
        local root = scaleNotes[chord.scaleNoteIndex]
        local chordData = scaleChords[chord.scaleNoteIndex][chord.chordTypeIndex]
        local octave = getOctave()
        local newNotes = getChordNotesArray(root, chordData, octave)
        

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
    if chord then

      setSelectedScaleNote(chord.scaleNoteIndex)
      setSelectedChordType(chord.scaleNoteIndex, chord.chordTypeIndex)
      
      local root = scaleNotes[chord.scaleNoteIndex]
      local chordData = scaleChords[chord.scaleNoteIndex][chord.chordTypeIndex]
      local octave = getOctave()
      local newNotes = getChordNotesArray(root, chordData, octave)
      

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

function previewScaleChord()

  local scaleNoteIndex = getSelectedScaleNote()
  local chordTypeIndex = getSelectedChordType(scaleNoteIndex)

  local root = scaleNotes[scaleNoteIndex]
  local chord = scaleChords[scaleNoteIndex][chordTypeIndex]
  local octave = getOctave()

  local chordNotesArray = getChordNotesArray(root, chord, octave)
  playScaleChord(chordNotesArray)
  updateChordText(root, chord, chordNotesArray)
end

function insertScaleChord(chordNotesArray, keepNotesSelected, selectedChord)

  deleteExistingNotesInNextInsertionTimePeriod(keepNotesSelected, selectedChord)

  for noteIndex = 1, #chordNotesArray do
    insertMidiNote(chordNotesArray[noteIndex], keepNotesSelected, selectedChord, noteIndex)
  end

  moveCursor(keepNotesSelected, selectedChord)
end

function ensureActiveTake()

  local take = activeTake()
  if take then return take end


  local track = reaper.GetSelectedTrack(0, 0)
  if not track then
    reaper.ShowMessageBox("No track selected.\nPlease select a track to insert chords.", "Error", 0)
    return nil
  end


  local startPos = reaper.GetCursorPosition()
  local startQN = reaper.TimeMap2_timeToQN(0, startPos)
  local endQN = startQN + 4
  local endPos = reaper.TimeMap2_QNToTime(0, endQN)

  local item = reaper.CreateNewMIDIItemInProj(track, startPos, endPos, false)
  if item then
    reaper.SetMediaItemSelected(item, true)
    reaper.UpdateArrange()
    return reaper.GetActiveTake(item)
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
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/ChordGun/src"


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
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/ChordGun/src"

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
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/ChordGun/src"

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
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/ChordGun/src"

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
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/ChordGun/src"

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

	setSelectedScaleNote(scaleNoteIndex)

	local selectedChordType = getSelectedChordType(scaleNoteIndex)
	local chord = scaleChords[scaleNoteIndex][selectedChordType]
	local actionDescription = "scale chord " .. scaleNoteIndex .. "  (" .. chord.code .. ")"

	playOrInsertScaleChord(actionDescription)
end

function previewScaleChordAction(scaleNoteIndex)

	if scaleIsPentatonic() and scaleNoteIndex > 5 then
		return
	end

	setSelectedScaleNote(scaleNoteIndex)
	previewScaleChord()
end

--

function scaleNoteAction(scaleNoteIndex)

	if scaleIsPentatonic() and scaleNoteIndex > 5 then
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

	setSelectedScaleNote(scaleNoteIndex)
	previewScaleNote(0)
end

function previewLowerScaleNoteAction(scaleNoteIndex)

	if scaleIsPentatonic() and scaleNoteIndex > 5 then
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

	if getOctave() >= getOctaveMax() then
		return
	end

	setSelectedScaleNote(scaleNoteIndex)
	previewScaleNote(1)
end
function drawDropdownIcon()

    local xOffset = gfx.x
    local yOffset = gfx.y
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 1 + xOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.y = 1 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = xOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 1 + xOffset
    gfx.y = 2 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.38823529411765)
    gfx.x = xOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 1 + xOffset
    gfx.y = 3 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = xOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 1 + xOffset
    gfx.y = 4 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = xOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 1 + xOffset
    gfx.y = 5 + yOffset
    gfx.setpixel(0.36078431372549, 0.39607843137255, 0.3843137254902)
    gfx.x = xOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 1 + xOffset
    gfx.y = 6 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = xOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 1 + xOffset
    gfx.y = 7 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = xOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 1 + xOffset
    gfx.y = 8 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = xOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 1 + xOffset
    gfx.y = 9 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = xOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 1 + xOffset
    gfx.y = 10 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = xOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 1 + xOffset
    gfx.y = 11 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = xOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 1 + xOffset
    gfx.y = 12 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = xOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 1 + xOffset
    gfx.y = 13 + yOffset
    gfx.setpixel(0.34901960784314, 0.37647058823529, 0.36470588235294)
    gfx.x = xOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 1 + xOffset
    gfx.y = 14 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 2 + xOffset
    gfx.y = yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.y = 1 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 2 + xOffset
    gfx.y = 2 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 2 + xOffset
    gfx.y = 3 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 2 + xOffset
    gfx.y = 4 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 2 + xOffset
    gfx.y = 5 + yOffset
    gfx.setpixel(0.3843137254902, 0.4156862745098, 0.40392156862745)
    gfx.x = 2 + xOffset
    gfx.y = 6 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 2 + xOffset
    gfx.y = 7 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 2 + xOffset
    gfx.y = 8 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 2 + xOffset
    gfx.y = 9 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 2 + xOffset
    gfx.y = 10 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 2 + xOffset
    gfx.y = 11 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 2 + xOffset
    gfx.y = 12 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 2 + xOffset
    gfx.y = 13 + yOffset
    gfx.setpixel(0.34901960784314, 0.37647058823529, 0.36470588235294)
    gfx.x = 2 + xOffset
    gfx.y = 14 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 3 + xOffset
    gfx.y = yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.y = 1 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 3 + xOffset
    gfx.y = 2 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 3 + xOffset
    gfx.y = 3 + yOffset
    gfx.setpixel(0.35294117647059, 0.3843137254902, 0.37254901960784)
    gfx.x = 3 + xOffset
    gfx.y = 4 + yOffset
    gfx.setpixel(0.41176470588235, 0.43921568627451, 0.42745098039216)
    gfx.x = 3 + xOffset
    gfx.y = 5 + yOffset
    gfx.setpixel(0.67843137254902, 0.69411764705882, 0.69019607843137)
    gfx.x = 3 + xOffset
    gfx.y = 6 + yOffset
    gfx.setpixel(0.50196078431373, 0.52549019607843, 0.51764705882353)
    gfx.x = 3 + xOffset
    gfx.y = 7 + yOffset
    gfx.setpixel(0.36078431372549, 0.39607843137255, 0.38039215686275)
    gfx.x = 3 + xOffset
    gfx.y = 8 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 3 + xOffset
    gfx.y = 9 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 3 + xOffset
    gfx.y = 10 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 3 + xOffset
    gfx.y = 11 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 3 + xOffset
    gfx.y = 12 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 3 + xOffset
    gfx.y = 13 + yOffset
    gfx.setpixel(0.34901960784314, 0.37647058823529, 0.36470588235294)
    gfx.x = 3 + xOffset
    gfx.y = 14 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 4 + xOffset
    gfx.y = yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.y = 1 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 4 + xOffset
    gfx.y = 2 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 4 + xOffset
    gfx.y = 3 + yOffset
    gfx.setpixel(0.34509803921569, 0.37647058823529, 0.36470588235294)
    gfx.x = 4 + xOffset
    gfx.y = 4 + yOffset
    gfx.setpixel(0.43529411764706, 0.46274509803922, 0.45098039215686)
    gfx.x = 4 + xOffset
    gfx.y = 5 + yOffset
    gfx.setpixel(0.92156862745098, 0.92549019607843, 0.92549019607843)
    gfx.x = 4 + xOffset
    gfx.y = 6 + yOffset
    gfx.setpixel(0.85882352941176, 0.86274509803922, 0.86274509803922)
    gfx.x = 4 + xOffset
    gfx.y = 7 + yOffset
    gfx.setpixel(0.53725490196078, 0.56078431372549, 0.55294117647059)
    gfx.x = 4 + xOffset
    gfx.y = 8 + yOffset
    gfx.setpixel(0.36470588235294, 0.4, 0.38823529411765)
    gfx.x = 4 + xOffset
    gfx.y = 9 + yOffset
    gfx.setpixel(0.36078431372549, 0.3921568627451, 0.38039215686275)
    gfx.x = 4 + xOffset
    gfx.y = 10 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 4 + xOffset
    gfx.y = 11 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 4 + xOffset
    gfx.y = 12 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 4 + xOffset
    gfx.y = 13 + yOffset
    gfx.setpixel(0.34901960784314, 0.37647058823529, 0.36470588235294)
    gfx.x = 4 + xOffset
    gfx.y = 14 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 5 + xOffset
    gfx.y = yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.y = 1 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 5 + xOffset
    gfx.y = 2 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 5 + xOffset
    gfx.y = 3 + yOffset
    gfx.setpixel(0.34509803921569, 0.38039215686275, 0.36470588235294)
    gfx.x = 5 + xOffset
    gfx.y = 4 + yOffset
    gfx.setpixel(0.43529411764706, 0.46274509803922, 0.45098039215686)
    gfx.x = 5 + xOffset
    gfx.y = 5 + yOffset
    gfx.setpixel(0.94901960784314, 0.95294117647059, 0.95294117647059)
    gfx.x = 5 + xOffset
    gfx.y = 6 + yOffset
    gfx.setpixel(1.0, 1.0, 1.0)
    gfx.x = 5 + xOffset
    gfx.y = 7 + yOffset
    gfx.setpixel(0.90196078431373, 0.90588235294118, 0.90196078431373)
    gfx.x = 5 + xOffset
    gfx.y = 8 + yOffset
    gfx.setpixel(0.6, 0.6156862745098, 0.61176470588235)
    gfx.x = 5 + xOffset
    gfx.y = 9 + yOffset
    gfx.setpixel(0.3921568627451, 0.42352941176471, 0.41176470588235)
    gfx.x = 5 + xOffset
    gfx.y = 10 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 5 + xOffset
    gfx.y = 11 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 5 + xOffset
    gfx.y = 12 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 5 + xOffset
    gfx.y = 13 + yOffset
    gfx.setpixel(0.34901960784314, 0.37647058823529, 0.36470588235294)
    gfx.x = 5 + xOffset
    gfx.y = 14 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 6 + xOffset
    gfx.y = yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.y = 1 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 6 + xOffset
    gfx.y = 2 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 6 + xOffset
    gfx.y = 3 + yOffset
    gfx.setpixel(0.34509803921569, 0.38039215686275, 0.36862745098039)
    gfx.x = 6 + xOffset
    gfx.y = 4 + yOffset
    gfx.setpixel(0.43529411764706, 0.46274509803922, 0.45098039215686)
    gfx.x = 6 + xOffset
    gfx.y = 5 + yOffset
    gfx.setpixel(0.94509803921569, 0.94509803921569, 0.94509803921569)
    gfx.x = 6 + xOffset
    gfx.y = 6 + yOffset
    gfx.setpixel(1.0, 1.0, 1.0)
    gfx.x = 6 + xOffset
    gfx.y = 7 + yOffset
    gfx.setpixel(1.0, 1.0, 1.0)
    gfx.x = 6 + xOffset
    gfx.y = 8 + yOffset
    gfx.setpixel(0.87058823529412, 0.87843137254902, 0.87843137254902)
    gfx.x = 6 + xOffset
    gfx.y = 9 + yOffset
    gfx.setpixel(0.52156862745098, 0.54509803921569, 0.53725490196078)
    gfx.x = 6 + xOffset
    gfx.y = 10 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.38823529411765)
    gfx.x = 6 + xOffset
    gfx.y = 11 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 6 + xOffset
    gfx.y = 12 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 6 + xOffset
    gfx.y = 13 + yOffset
    gfx.setpixel(0.34901960784314, 0.37647058823529, 0.36470588235294)
    gfx.x = 6 + xOffset
    gfx.y = 14 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 7 + xOffset
    gfx.y = yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.y = 1 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 7 + xOffset
    gfx.y = 2 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 7 + xOffset
    gfx.y = 3 + yOffset
    gfx.setpixel(0.34509803921569, 0.38039215686275, 0.36470588235294)
    gfx.x = 7 + xOffset
    gfx.y = 4 + yOffset
    gfx.setpixel(0.43529411764706, 0.46274509803922, 0.45098039215686)
    gfx.x = 7 + xOffset
    gfx.y = 5 + yOffset
    gfx.setpixel(0.94901960784314, 0.95294117647059, 0.95294117647059)
    gfx.x = 7 + xOffset
    gfx.y = 6 + yOffset
    gfx.setpixel(1.0, 1.0, 1.0)
    gfx.x = 7 + xOffset
    gfx.y = 7 + yOffset
    gfx.setpixel(0.90196078431373, 0.90588235294118, 0.90196078431373)
    gfx.x = 7 + xOffset
    gfx.y = 8 + yOffset
    gfx.setpixel(0.6, 0.6156862745098, 0.61176470588235)
    gfx.x = 7 + xOffset
    gfx.y = 9 + yOffset
    gfx.setpixel(0.3921568627451, 0.42352941176471, 0.41176470588235)
    gfx.x = 7 + xOffset
    gfx.y = 10 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 7 + xOffset
    gfx.y = 11 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 7 + xOffset
    gfx.y = 12 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 7 + xOffset
    gfx.y = 13 + yOffset
    gfx.setpixel(0.34901960784314, 0.37647058823529, 0.36470588235294)
    gfx.x = 7 + xOffset
    gfx.y = 14 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 8 + xOffset
    gfx.y = yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.y = 1 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 8 + xOffset
    gfx.y = 2 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 8 + xOffset
    gfx.y = 3 + yOffset
    gfx.setpixel(0.34509803921569, 0.37647058823529, 0.36470588235294)
    gfx.x = 8 + xOffset
    gfx.y = 4 + yOffset
    gfx.setpixel(0.43529411764706, 0.46274509803922, 0.45490196078431)
    gfx.x = 8 + xOffset
    gfx.y = 5 + yOffset
    gfx.setpixel(0.92156862745098, 0.92549019607843, 0.92549019607843)
    gfx.x = 8 + xOffset
    gfx.y = 6 + yOffset
    gfx.setpixel(0.85490196078431, 0.86274509803922, 0.85882352941176)
    gfx.x = 8 + xOffset
    gfx.y = 7 + yOffset
    gfx.setpixel(0.53725490196078, 0.56078431372549, 0.55294117647059)
    gfx.x = 8 + xOffset
    gfx.y = 8 + yOffset
    gfx.setpixel(0.36470588235294, 0.4, 0.38823529411765)
    gfx.x = 8 + xOffset
    gfx.y = 9 + yOffset
    gfx.setpixel(0.36078431372549, 0.3921568627451, 0.38039215686275)
    gfx.x = 8 + xOffset
    gfx.y = 10 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 8 + xOffset
    gfx.y = 11 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 8 + xOffset
    gfx.y = 12 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 8 + xOffset
    gfx.y = 13 + yOffset
    gfx.setpixel(0.34901960784314, 0.37647058823529, 0.36470588235294)
    gfx.x = 8 + xOffset
    gfx.y = 14 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 9 + xOffset
    gfx.y = yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.y = 1 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 9 + xOffset
    gfx.y = 2 + yOffset
    gfx.setpixel(0.36862745098039, 0.39607843137255, 0.3843137254902)
    gfx.x = 9 + xOffset
    gfx.y = 3 + yOffset
    gfx.setpixel(0.35294117647059, 0.3843137254902, 0.37254901960784)
    gfx.x = 9 + xOffset
    gfx.y = 4 + yOffset
    gfx.setpixel(0.41176470588235, 0.43921568627451, 0.42745098039216)
    gfx.x = 9 + xOffset
    gfx.y = 5 + yOffset
    gfx.setpixel(0.67843137254902, 0.69411764705882, 0.69019607843137)
    gfx.x = 9 + xOffset
    gfx.y = 6 + yOffset
    gfx.setpixel(0.49803921568627, 0.52549019607843, 0.51764705882353)
    gfx.x = 9 + xOffset
    gfx.y = 7 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 9 + xOffset
    gfx.y = 8 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 9 + xOffset
    gfx.y = 9 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 9 + xOffset
    gfx.y = 10 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 9 + xOffset
    gfx.y = 11 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 9 + xOffset
    gfx.y = 12 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 9 + xOffset
    gfx.y = 13 + yOffset
    gfx.setpixel(0.34901960784314, 0.37647058823529, 0.36470588235294)
    gfx.x = 9 + xOffset
    gfx.y = 14 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 10 + xOffset
    gfx.y = yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.y = 1 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 10 + xOffset
    gfx.y = 2 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 10 + xOffset
    gfx.y = 3 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 10 + xOffset
    gfx.y = 4 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 10 + xOffset
    gfx.y = 5 + yOffset
    gfx.setpixel(0.3843137254902, 0.4156862745098, 0.40392156862745)
    gfx.x = 10 + xOffset
    gfx.y = 6 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 10 + xOffset
    gfx.y = 7 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 10 + xOffset
    gfx.y = 8 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 10 + xOffset
    gfx.y = 9 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 10 + xOffset
    gfx.y = 10 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 10 + xOffset
    gfx.y = 11 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 10 + xOffset
    gfx.y = 12 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 10 + xOffset
    gfx.y = 13 + yOffset
    gfx.setpixel(0.34901960784314, 0.37647058823529, 0.36470588235294)
    gfx.x = 10 + xOffset
    gfx.y = 14 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 11 + xOffset
    gfx.y = yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.y = 1 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 11 + xOffset
    gfx.y = 2 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 11 + xOffset
    gfx.y = 3 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 11 + xOffset
    gfx.y = 4 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 11 + xOffset
    gfx.y = 5 + yOffset
    gfx.setpixel(0.36078431372549, 0.3921568627451, 0.38039215686275)
    gfx.x = 11 + xOffset
    gfx.y = 6 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 11 + xOffset
    gfx.y = 7 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 11 + xOffset
    gfx.y = 8 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 11 + xOffset
    gfx.y = 9 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 11 + xOffset
    gfx.y = 10 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 11 + xOffset
    gfx.y = 11 + yOffset
    gfx.setpixel(0.36470588235294, 0.39607843137255, 0.3843137254902)
    gfx.x = 11 + xOffset
    gfx.y = 12 + yOffset
    gfx.setpixel(0.36470588235294, 0.4, 0.38823529411765)
    gfx.x = 11 + xOffset
    gfx.y = 13 + yOffset
    gfx.setpixel(0.34509803921569, 0.37647058823529, 0.36470588235294)
    gfx.x = 11 + xOffset
    gfx.y = 14 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 12 + xOffset
    gfx.y = yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.y = 1 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 12 + xOffset
    gfx.y = 2 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 12 + xOffset
    gfx.y = 3 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 12 + xOffset
    gfx.y = 4 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 12 + xOffset
    gfx.y = 5 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 12 + xOffset
    gfx.y = 6 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 12 + xOffset
    gfx.y = 7 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 12 + xOffset
    gfx.y = 8 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 12 + xOffset
    gfx.y = 9 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 12 + xOffset
    gfx.y = 10 + yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.x = 12 + xOffset
    gfx.y = 11 + yOffset
    gfx.setpixel(0.36470588235294, 0.4, 0.38823529411765)
    gfx.x = 12 + xOffset
    gfx.y = 12 + yOffset
    gfx.setpixel(0.36862745098039, 0.40392156862745, 0.3921568627451)
    gfx.x = 12 + xOffset
    gfx.y = 13 + yOffset
    gfx.setpixel(0.34901960784314, 0.38039215686275, 0.36862745098039)
    gfx.x = 12 + xOffset
    gfx.y = 14 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 13 + xOffset
    gfx.y = yOffset
    gfx.setpixel(0.36862745098039, 0.4, 0.38823529411765)
    gfx.y = 1 + yOffset
    gfx.setpixel(0.34901960784314, 0.38039215686275, 0.36862745098039)
    gfx.x = 13 + xOffset
    gfx.y = 2 + yOffset
    gfx.setpixel(0.34509803921569, 0.37647058823529, 0.36470588235294)
    gfx.x = 13 + xOffset
    gfx.y = 3 + yOffset
    gfx.setpixel(0.34901960784314, 0.37647058823529, 0.36470588235294)
    gfx.x = 13 + xOffset
    gfx.y = 4 + yOffset
    gfx.setpixel(0.34901960784314, 0.37647058823529, 0.36470588235294)
    gfx.x = 13 + xOffset
    gfx.y = 5 + yOffset
    gfx.setpixel(0.34901960784314, 0.37647058823529, 0.36470588235294)
    gfx.x = 13 + xOffset
    gfx.y = 6 + yOffset
    gfx.setpixel(0.34901960784314, 0.37647058823529, 0.36470588235294)
    gfx.x = 13 + xOffset
    gfx.y = 7 + yOffset
    gfx.setpixel(0.34901960784314, 0.37647058823529, 0.36470588235294)
    gfx.x = 13 + xOffset
    gfx.y = 8 + yOffset
    gfx.setpixel(0.34901960784314, 0.37647058823529, 0.36470588235294)
    gfx.x = 13 + xOffset
    gfx.y = 9 + yOffset
    gfx.setpixel(0.34901960784314, 0.37647058823529, 0.36470588235294)
    gfx.x = 13 + xOffset
    gfx.y = 10 + yOffset
    gfx.setpixel(0.34901960784314, 0.37647058823529, 0.36470588235294)
    gfx.x = 13 + xOffset
    gfx.y = 11 + yOffset
    gfx.setpixel(0.34509803921569, 0.37647058823529, 0.36470588235294)
    gfx.x = 13 + xOffset
    gfx.y = 12 + yOffset
    gfx.setpixel(0.34901960784314, 0.38039215686275, 0.36862745098039)
    gfx.x = 13 + xOffset
    gfx.y = 13 + yOffset
    gfx.setpixel(0.32549019607843, 0.35294117647059, 0.34117647058824)
    gfx.x = 13 + xOffset
    gfx.y = 14 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 14 + xOffset
    gfx.y = 1 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 14 + xOffset
    gfx.y = 2 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 14 + xOffset
    gfx.y = 3 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 14 + xOffset
    gfx.y = 4 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 14 + xOffset
    gfx.y = 5 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 14 + xOffset
    gfx.y = 6 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 14 + xOffset
    gfx.y = 7 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 14 + xOffset
    gfx.y = 8 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 14 + xOffset
    gfx.y = 9 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 14 + xOffset
    gfx.y = 10 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 14 + xOffset
    gfx.y = 11 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 14 + xOffset
    gfx.y = 12 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 14 + xOffset
    gfx.y = 13 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 14 + xOffset
    gfx.y = 14 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
end
function drawLeftArrow()

    local xOffset = gfx.x
    local yOffset = gfx.y
    gfx.x = 1 + xOffset
    gfx.y = 1 + yOffset
    gfx.setpixel(0.086274509803922, 0.086274509803922, 0.086274509803922)
    gfx.x = 1 + xOffset
    gfx.y = 2 + yOffset
    gfx.setpixel(0.086274509803922, 0.086274509803922, 0.086274509803922)
    gfx.x = 1 + xOffset
    gfx.y = 3 + yOffset
    gfx.setpixel(0.10196078431373, 0.10196078431373, 0.10196078431373)
    gfx.x = 1 + xOffset
    gfx.y = 4 + yOffset
    gfx.setpixel(0.18823529411765, 0.1921568627451, 0.1921568627451)
    gfx.x = 1 + xOffset
    gfx.y = 5 + yOffset
    gfx.setpixel(0.10196078431373, 0.10196078431373, 0.10196078431373)
    gfx.x = 1 + xOffset
    gfx.y = 6 + yOffset
    gfx.setpixel(0.086274509803922, 0.086274509803922, 0.086274509803922)
    gfx.x = 1 + xOffset
    gfx.y = 7 + yOffset
    gfx.setpixel(0.086274509803922, 0.086274509803922, 0.086274509803922)
    gfx.x = 1 + xOffset
    gfx.y = 8 + yOffset
    gfx.setpixel(0.086274509803922, 0.086274509803922, 0.086274509803922)
    gfx.x = 1 + xOffset
    gfx.y = 9 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 2 + xOffset
    gfx.y = 1 + yOffset
    gfx.setpixel(0.086274509803922, 0.086274509803922, 0.086274509803922)
    gfx.x = 2 + xOffset
    gfx.y = 2 + yOffset
    gfx.setpixel(0.07843137254902, 0.07843137254902, 0.074509803921569)
    gfx.x = 2 + xOffset
    gfx.y = 3 + yOffset
    gfx.setpixel(0.24313725490196, 0.25882352941176, 0.25882352941176)
    gfx.x = 2 + xOffset
    gfx.y = 4 + yOffset
    gfx.setpixel(0.45490196078431, 0.48627450980392, 0.49019607843137)
    gfx.x = 2 + xOffset
    gfx.y = 5 + yOffset
    gfx.setpixel(0.24313725490196, 0.25882352941176, 0.25882352941176)
    gfx.x = 2 + xOffset
    gfx.y = 6 + yOffset
    gfx.setpixel(0.07843137254902, 0.07843137254902, 0.074509803921569)
    gfx.x = 2 + xOffset
    gfx.y = 7 + yOffset
    gfx.setpixel(0.086274509803922, 0.086274509803922, 0.086274509803922)
    gfx.x = 2 + xOffset
    gfx.y = 8 + yOffset
    gfx.setpixel(0.086274509803922, 0.086274509803922, 0.086274509803922)
    gfx.x = 2 + xOffset
    gfx.y = 9 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 3 + xOffset
    gfx.y = 1 + yOffset
    gfx.setpixel(0.07843137254902, 0.07843137254902, 0.07843137254902)
    gfx.x = 3 + xOffset
    gfx.y = 2 + yOffset
    gfx.setpixel(0.19607843137255, 0.2078431372549, 0.2078431372549)
    gfx.x = 3 + xOffset
    gfx.y = 3 + yOffset
    gfx.setpixel(0.47450980392157, 0.51372549019608, 0.51372549019608)
    gfx.x = 3 + xOffset
    gfx.y = 4 + yOffset
    gfx.setpixel(0.56078431372549, 0.61176470588235, 0.61176470588235)
    gfx.x = 3 + xOffset
    gfx.y = 5 + yOffset
    gfx.setpixel(0.47450980392157, 0.51372549019608, 0.51372549019608)
    gfx.x = 3 + xOffset
    gfx.y = 6 + yOffset
    gfx.setpixel(0.19607843137255, 0.2078431372549, 0.2078431372549)
    gfx.x = 3 + xOffset
    gfx.y = 7 + yOffset
    gfx.setpixel(0.07843137254902, 0.07843137254902, 0.07843137254902)
    gfx.x = 3 + xOffset
    gfx.y = 8 + yOffset
    gfx.setpixel(0.090196078431373, 0.090196078431373, 0.090196078431373)
    gfx.x = 3 + xOffset
    gfx.y = 9 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 4 + xOffset
    gfx.y = 1 + yOffset
    gfx.setpixel(0.19607843137255, 0.2078431372549, 0.2078431372549)
    gfx.x = 4 + xOffset
    gfx.y = 2 + yOffset
    gfx.setpixel(0.44313725490196, 0.47843137254902, 0.47843137254902)
    gfx.x = 4 + xOffset
    gfx.y = 3 + yOffset
    gfx.setpixel(0.56862745098039, 0.6156862745098, 0.61176470588235)
    gfx.x = 4 + xOffset
    gfx.y = 4 + yOffset
    gfx.setpixel(0.57647058823529, 0.62352941176471, 0.62352941176471)
    gfx.x = 4 + xOffset
    gfx.y = 5 + yOffset
    gfx.setpixel(0.56862745098039, 0.6156862745098, 0.61176470588235)
    gfx.x = 4 + xOffset
    gfx.y = 6 + yOffset
    gfx.setpixel(0.44313725490196, 0.47843137254902, 0.47843137254902)
    gfx.x = 4 + xOffset
    gfx.y = 7 + yOffset
    gfx.setpixel(0.19607843137255, 0.2078431372549, 0.2078431372549)
    gfx.x = 4 + xOffset
    gfx.y = 8 + yOffset
    gfx.setpixel(0.086274509803922, 0.086274509803922, 0.086274509803922)
    gfx.x = 4 + xOffset
    gfx.y = 9 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 5 + xOffset
    gfx.y = 1 + yOffset
    gfx.setpixel(0.30196078431373, 0.32156862745098, 0.32156862745098)
    gfx.x = 5 + xOffset
    gfx.y = 2 + yOffset
    gfx.setpixel(0.49411764705882, 0.53725490196078, 0.53725490196078)
    gfx.x = 5 + xOffset
    gfx.y = 3 + yOffset
    gfx.setpixel(0.51764705882353, 0.56470588235294, 0.56470588235294)
    gfx.x = 5 + xOffset
    gfx.y = 4 + yOffset
    gfx.setpixel(0.51372549019608, 0.55686274509804, 0.55686274509804)
    gfx.x = 5 + xOffset
    gfx.y = 5 + yOffset
    gfx.setpixel(0.51764705882353, 0.56470588235294, 0.56470588235294)
    gfx.x = 5 + xOffset
    gfx.y = 6 + yOffset
    gfx.setpixel(0.49411764705882, 0.53725490196078, 0.53725490196078)
    gfx.x = 5 + xOffset
    gfx.y = 7 + yOffset
    gfx.setpixel(0.30196078431373, 0.32156862745098, 0.32156862745098)
    gfx.x = 5 + xOffset
    gfx.y = 8 + yOffset
    gfx.setpixel(0.098039215686275, 0.098039215686275, 0.098039215686275)
    gfx.x = 5 + xOffset
    gfx.y = 9 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 6 + xOffset
    gfx.y = 1 + yOffset
    gfx.setpixel(0.11764705882353, 0.12156862745098, 0.12156862745098)
    gfx.x = 6 + xOffset
    gfx.y = 2 + yOffset
    gfx.setpixel(0.13725490196078, 0.14117647058824, 0.14117647058824)
    gfx.x = 6 + xOffset
    gfx.y = 3 + yOffset
    gfx.setpixel(0.13333333333333, 0.13725490196078, 0.13725490196078)
    gfx.x = 6 + xOffset
    gfx.y = 4 + yOffset
    gfx.setpixel(0.13333333333333, 0.13725490196078, 0.13725490196078)
    gfx.x = 6 + xOffset
    gfx.y = 5 + yOffset
    gfx.setpixel(0.13333333333333, 0.13725490196078, 0.13725490196078)
    gfx.x = 6 + xOffset
    gfx.y = 6 + yOffset
    gfx.setpixel(0.13725490196078, 0.14117647058824, 0.14117647058824)
    gfx.x = 6 + xOffset
    gfx.y = 7 + yOffset
    gfx.setpixel(0.11764705882353, 0.12156862745098, 0.12156862745098)
    gfx.x = 6 + xOffset
    gfx.y = 8 + yOffset
    gfx.setpixel(0.086274509803922, 0.086274509803922, 0.086274509803922)
    gfx.x = 6 + xOffset
    gfx.y = 9 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 7 + xOffset
    gfx.y = 1 + yOffset
    gfx.setpixel(0.07843137254902, 0.074509803921569, 0.074509803921569)
    gfx.x = 7 + xOffset
    gfx.y = 2 + yOffset
    gfx.setpixel(0.070588235294118, 0.066666666666667, 0.066666666666667)
    gfx.x = 7 + xOffset
    gfx.y = 3 + yOffset
    gfx.setpixel(0.070588235294118, 0.066666666666667, 0.066666666666667)
    gfx.x = 7 + xOffset
    gfx.y = 4 + yOffset
    gfx.setpixel(0.070588235294118, 0.070588235294118, 0.070588235294118)
    gfx.x = 7 + xOffset
    gfx.y = 5 + yOffset
    gfx.setpixel(0.070588235294118, 0.066666666666667, 0.066666666666667)
    gfx.x = 7 + xOffset
    gfx.y = 6 + yOffset
    gfx.setpixel(0.070588235294118, 0.066666666666667, 0.066666666666667)
    gfx.x = 7 + xOffset
    gfx.y = 7 + yOffset
    gfx.setpixel(0.07843137254902, 0.074509803921569, 0.074509803921569)
    gfx.x = 7 + xOffset
    gfx.y = 8 + yOffset
    gfx.setpixel(0.086274509803922, 0.086274509803922, 0.086274509803922)
    gfx.x = 7 + xOffset
    gfx.y = 9 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 8 + xOffset
    gfx.y = 1 + yOffset
    gfx.setpixel(0.086274509803922, 0.090196078431373, 0.090196078431373)
    gfx.x = 8 + xOffset
    gfx.y = 2 + yOffset
    gfx.setpixel(0.090196078431373, 0.090196078431373, 0.090196078431373)
    gfx.x = 8 + xOffset
    gfx.y = 3 + yOffset
    gfx.setpixel(0.090196078431373, 0.090196078431373, 0.090196078431373)
    gfx.x = 8 + xOffset
    gfx.y = 4 + yOffset
    gfx.setpixel(0.090196078431373, 0.090196078431373, 0.090196078431373)
    gfx.x = 8 + xOffset
    gfx.y = 5 + yOffset
    gfx.setpixel(0.090196078431373, 0.090196078431373, 0.090196078431373)
    gfx.x = 8 + xOffset
    gfx.y = 6 + yOffset
    gfx.setpixel(0.090196078431373, 0.090196078431373, 0.090196078431373)
    gfx.x = 8 + xOffset
    gfx.y = 7 + yOffset
    gfx.setpixel(0.086274509803922, 0.090196078431373, 0.090196078431373)
    gfx.x = 8 + xOffset
    gfx.y = 8 + yOffset
    gfx.setpixel(0.086274509803922, 0.086274509803922, 0.086274509803922)
    gfx.x = 8 + xOffset
    gfx.y = 9 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 9 + xOffset
    gfx.y = 1 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 9 + xOffset
    gfx.y = 2 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 9 + xOffset
    gfx.y = 3 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 9 + xOffset
    gfx.y = 4 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 9 + xOffset
    gfx.y = 5 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 9 + xOffset
    gfx.y = 6 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 9 + xOffset
    gfx.y = 7 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 9 + xOffset
    gfx.y = 8 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 9 + xOffset
    gfx.y = 9 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
end
function drawRightArrow()

    local xOffset = gfx.x
    local yOffset = gfx.y
    gfx.x = 1 + xOffset
    gfx.y = 1 + yOffset
    gfx.setpixel(0.07843137254902, 0.074509803921569, 0.074509803921569)
    gfx.x = 1 + xOffset
    gfx.y = 2 + yOffset
    gfx.setpixel(0.070588235294118, 0.066666666666667, 0.066666666666667)
    gfx.x = 1 + xOffset
    gfx.y = 3 + yOffset
    gfx.setpixel(0.070588235294118, 0.066666666666667, 0.066666666666667)
    gfx.x = 1 + xOffset
    gfx.y = 4 + yOffset
    gfx.setpixel(0.070588235294118, 0.070588235294118, 0.070588235294118)
    gfx.x = 1 + xOffset
    gfx.y = 5 + yOffset
    gfx.setpixel(0.070588235294118, 0.066666666666667, 0.066666666666667)
    gfx.x = 1 + xOffset
    gfx.y = 6 + yOffset
    gfx.setpixel(0.070588235294118, 0.066666666666667, 0.066666666666667)
    gfx.x = 1 + xOffset
    gfx.y = 7 + yOffset
    gfx.setpixel(0.07843137254902, 0.074509803921569, 0.074509803921569)
    gfx.x = 1 + xOffset
    gfx.y = 8 + yOffset
    gfx.setpixel(0.086274509803922, 0.086274509803922, 0.086274509803922)
    gfx.x = 1 + xOffset
    gfx.y = 9 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 2 + xOffset
    gfx.y = 1 + yOffset
    gfx.setpixel(0.11764705882353, 0.12156862745098, 0.12156862745098)
    gfx.x = 2 + xOffset
    gfx.y = 2 + yOffset
    gfx.setpixel(0.13725490196078, 0.14117647058824, 0.14117647058824)
    gfx.x = 2 + xOffset
    gfx.y = 3 + yOffset
    gfx.setpixel(0.13333333333333, 0.13725490196078, 0.13725490196078)
    gfx.x = 2 + xOffset
    gfx.y = 4 + yOffset
    gfx.setpixel(0.13333333333333, 0.13725490196078, 0.13725490196078)
    gfx.x = 2 + xOffset
    gfx.y = 5 + yOffset
    gfx.setpixel(0.13333333333333, 0.13725490196078, 0.13725490196078)
    gfx.x = 2 + xOffset
    gfx.y = 6 + yOffset
    gfx.setpixel(0.13725490196078, 0.14117647058824, 0.14117647058824)
    gfx.x = 2 + xOffset
    gfx.y = 7 + yOffset
    gfx.setpixel(0.11764705882353, 0.12156862745098, 0.12156862745098)
    gfx.x = 2 + xOffset
    gfx.y = 8 + yOffset
    gfx.setpixel(0.086274509803922, 0.086274509803922, 0.086274509803922)
    gfx.x = 2 + xOffset
    gfx.y = 9 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 3 + xOffset
    gfx.y = 1 + yOffset
    gfx.setpixel(0.30196078431373, 0.32156862745098, 0.32156862745098)
    gfx.x = 3 + xOffset
    gfx.y = 2 + yOffset
    gfx.setpixel(0.49411764705882, 0.53725490196078, 0.53725490196078)
    gfx.x = 3 + xOffset
    gfx.y = 3 + yOffset
    gfx.setpixel(0.51764705882353, 0.56470588235294, 0.56470588235294)
    gfx.x = 3 + xOffset
    gfx.y = 4 + yOffset
    gfx.setpixel(0.51372549019608, 0.55686274509804, 0.55686274509804)
    gfx.x = 3 + xOffset
    gfx.y = 5 + yOffset
    gfx.setpixel(0.51764705882353, 0.56470588235294, 0.56470588235294)
    gfx.x = 3 + xOffset
    gfx.y = 6 + yOffset
    gfx.setpixel(0.49411764705882, 0.53725490196078, 0.53725490196078)
    gfx.x = 3 + xOffset
    gfx.y = 7 + yOffset
    gfx.setpixel(0.30196078431373, 0.32156862745098, 0.32156862745098)
    gfx.x = 3 + xOffset
    gfx.y = 8 + yOffset
    gfx.setpixel(0.098039215686275, 0.098039215686275, 0.098039215686275)
    gfx.x = 3 + xOffset
    gfx.y = 9 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 4 + xOffset
    gfx.y = 1 + yOffset
    gfx.setpixel(0.19607843137255, 0.2078431372549, 0.2078431372549)
    gfx.x = 4 + xOffset
    gfx.y = 2 + yOffset
    gfx.setpixel(0.44313725490196, 0.47843137254902, 0.47843137254902)
    gfx.x = 4 + xOffset
    gfx.y = 3 + yOffset
    gfx.setpixel(0.56862745098039, 0.6156862745098, 0.61176470588235)
    gfx.x = 4 + xOffset
    gfx.y = 4 + yOffset
    gfx.setpixel(0.57647058823529, 0.62352941176471, 0.62352941176471)
    gfx.x = 4 + xOffset
    gfx.y = 5 + yOffset
    gfx.setpixel(0.56862745098039, 0.6156862745098, 0.61176470588235)
    gfx.x = 4 + xOffset
    gfx.y = 6 + yOffset
    gfx.setpixel(0.44313725490196, 0.47843137254902, 0.47843137254902)
    gfx.x = 4 + xOffset
    gfx.y = 7 + yOffset
    gfx.setpixel(0.19607843137255, 0.2078431372549, 0.2078431372549)
    gfx.x = 4 + xOffset
    gfx.y = 8 + yOffset
    gfx.setpixel(0.086274509803922, 0.086274509803922, 0.086274509803922)
    gfx.x = 4 + xOffset
    gfx.y = 9 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 5 + xOffset
    gfx.y = 1 + yOffset
    gfx.setpixel(0.07843137254902, 0.07843137254902, 0.07843137254902)
    gfx.x = 5 + xOffset
    gfx.y = 2 + yOffset
    gfx.setpixel(0.19607843137255, 0.2078431372549, 0.2078431372549)
    gfx.x = 5 + xOffset
    gfx.y = 3 + yOffset
    gfx.setpixel(0.47450980392157, 0.51372549019608, 0.51372549019608)
    gfx.x = 5 + xOffset
    gfx.y = 4 + yOffset
    gfx.setpixel(0.56078431372549, 0.61176470588235, 0.61176470588235)
    gfx.x = 5 + xOffset
    gfx.y = 5 + yOffset
    gfx.setpixel(0.47450980392157, 0.51372549019608, 0.51372549019608)
    gfx.x = 5 + xOffset
    gfx.y = 6 + yOffset
    gfx.setpixel(0.19607843137255, 0.2078431372549, 0.2078431372549)
    gfx.x = 5 + xOffset
    gfx.y = 7 + yOffset
    gfx.setpixel(0.07843137254902, 0.07843137254902, 0.07843137254902)
    gfx.x = 5 + xOffset
    gfx.y = 8 + yOffset
    gfx.setpixel(0.090196078431373, 0.090196078431373, 0.090196078431373)
    gfx.x = 5 + xOffset
    gfx.y = 9 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 6 + xOffset
    gfx.y = 1 + yOffset
    gfx.setpixel(0.086274509803922, 0.086274509803922, 0.086274509803922)
    gfx.x = 6 + xOffset
    gfx.y = 2 + yOffset
    gfx.setpixel(0.07843137254902, 0.07843137254902, 0.074509803921569)
    gfx.x = 6 + xOffset
    gfx.y = 3 + yOffset
    gfx.setpixel(0.24313725490196, 0.25882352941176, 0.25882352941176)
    gfx.x = 6 + xOffset
    gfx.y = 4 + yOffset
    gfx.setpixel(0.45490196078431, 0.48627450980392, 0.49019607843137)
    gfx.x = 6 + xOffset
    gfx.y = 5 + yOffset
    gfx.setpixel(0.24313725490196, 0.25882352941176, 0.25882352941176)
    gfx.x = 6 + xOffset
    gfx.y = 6 + yOffset
    gfx.setpixel(0.07843137254902, 0.07843137254902, 0.074509803921569)
    gfx.x = 6 + xOffset
    gfx.y = 7 + yOffset
    gfx.setpixel(0.086274509803922, 0.086274509803922, 0.086274509803922)
    gfx.x = 6 + xOffset
    gfx.y = 8 + yOffset
    gfx.setpixel(0.086274509803922, 0.086274509803922, 0.086274509803922)
    gfx.x = 6 + xOffset
    gfx.y = 9 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 7 + xOffset
    gfx.y = 1 + yOffset
    gfx.setpixel(0.086274509803922, 0.086274509803922, 0.086274509803922)
    gfx.x = 7 + xOffset
    gfx.y = 2 + yOffset
    gfx.setpixel(0.086274509803922, 0.086274509803922, 0.086274509803922)
    gfx.x = 7 + xOffset
    gfx.y = 3 + yOffset
    gfx.setpixel(0.10196078431373, 0.10196078431373, 0.10196078431373)
    gfx.x = 7 + xOffset
    gfx.y = 4 + yOffset
    gfx.setpixel(0.18823529411765, 0.1921568627451, 0.1921568627451)
    gfx.x = 7 + xOffset
    gfx.y = 5 + yOffset
    gfx.setpixel(0.10196078431373, 0.10196078431373, 0.10196078431373)
    gfx.x = 7 + xOffset
    gfx.y = 6 + yOffset
    gfx.setpixel(0.086274509803922, 0.086274509803922, 0.086274509803922)
    gfx.x = 7 + xOffset
    gfx.y = 7 + yOffset
    gfx.setpixel(0.086274509803922, 0.086274509803922, 0.086274509803922)
    gfx.x = 7 + xOffset
    gfx.y = 8 + yOffset
    gfx.setpixel(0.086274509803922, 0.086274509803922, 0.086274509803922)
    gfx.x = 7 + xOffset
    gfx.y = 9 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 8 + xOffset
    gfx.y = 1 + yOffset
    gfx.setpixel(0.086274509803922, 0.086274509803922, 0.086274509803922)
    gfx.x = 8 + xOffset
    gfx.y = 2 + yOffset
    gfx.setpixel(0.086274509803922, 0.086274509803922, 0.086274509803922)
    gfx.x = 8 + xOffset
    gfx.y = 3 + yOffset
    gfx.setpixel(0.086274509803922, 0.086274509803922, 0.086274509803922)
    gfx.x = 8 + xOffset
    gfx.y = 4 + yOffset
    gfx.setpixel(0.086274509803922, 0.082352941176471, 0.082352941176471)
    gfx.x = 8 + xOffset
    gfx.y = 5 + yOffset
    gfx.setpixel(0.086274509803922, 0.086274509803922, 0.086274509803922)
    gfx.x = 8 + xOffset
    gfx.y = 6 + yOffset
    gfx.setpixel(0.086274509803922, 0.086274509803922, 0.086274509803922)
    gfx.x = 8 + xOffset
    gfx.y = 7 + yOffset
    gfx.setpixel(0.086274509803922, 0.086274509803922, 0.086274509803922)
    gfx.x = 8 + xOffset
    gfx.y = 8 + yOffset
    gfx.setpixel(0.086274509803922, 0.086274509803922, 0.086274509803922)
    gfx.x = 8 + xOffset
    gfx.y = 9 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 9 + xOffset
    gfx.y = 1 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 9 + xOffset
    gfx.y = 2 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 9 + xOffset
    gfx.y = 3 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 9 + xOffset
    gfx.y = 4 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 9 + xOffset
    gfx.y = 5 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 9 + xOffset
    gfx.y = 6 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 9 + xOffset
    gfx.y = 7 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 9 + xOffset
    gfx.y = 8 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
    gfx.x = 9 + xOffset
    gfx.y = 9 + yOffset
    gfx.setpixel(0.0, 0.0, 0.0)
end
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

--[[ window ]]--

function setDrawColorToBackground()
	setColor("242424")
end

--[[ buttons ]]--

function setDrawColorToNormalButton()
	setColor("2D2D2D")
end

function setDrawColorToHighlightedButton()
	setColor("474747")
end

function setDrawColorToPressedButton()
	setColor("FFD700")
end

function setDrawColorToPressedButtonText()
	setColor("1A1A1A")
end

--

function setDrawColorToSelectedChordTypeButton()
	setColor("474747")
end

function setDrawColorToHighlightedSelectedChordTypeButton()
	setColor("717171")
end

--

function setDrawColorToSelectedChordTypeAndScaleNoteButton()
	setColor("DCDCDC")
end

function setDrawColorToHighlightedSelectedChordTypeAndScaleNoteButton()
	setColor("FFFFFF")
end

--

function setDrawColorToOutOfScaleButton()
	setColor("121212")
end

function setDrawColorToHighlightedOutOfScaleButton()
	setColor("474747")
end

--

function setDrawColorToButtonOutline()
	setColor("1D1D1D")
end

--[[ button text ]]--

function setDrawColorToNormalButtonText()
	setColor("D7D7D7")
end

function setDrawColorToHighlightedButtonText()
	setColor("EEEEEE")
end

--

function setDrawColorToSelectedChordTypeButtonText()
	setColor("F1F1F1")
end

function setDrawColorToHighlightedSelectedChordTypeButtonText()
	setColor("FDFDFD")
end

--

function setDrawColorToSelectedChordTypeAndScaleNoteButtonText()
	setColor("121212")
end

function setDrawColorToHighlightedSelectedChordTypeAndScaleNoteButtonText()
	setColor("000000")
end

--[[ buttons ]]--

function setDrawColorToHeaderOutline()
	setColor("2E5C8A")
end

function setDrawColorToHeaderBackground()
	setColor("4A90D9")
end

function setDrawColorToHeaderText()
	setColor("E8F4FF")
end


--[[ frame ]]--
function setDrawColorToFrameOutline()
	setColor("0D0D0D")
end

function setDrawColorToFrameBackground()
	setColor("181818")
end


--[[ dropdown ]]--
function setDrawColorToDropdownOutline()
	setColor("090909")
end

function setDrawColorToDropdownBackground()
	setColor("1D1D1D")
end

function setDrawColorToDropdownText()
	setColor("D7D7D7")
end

--[[ valuebox ]]--
function setDrawColorToValueBoxOutline()
	setColor("090909")
end

function setDrawColorToValueBoxBackground()
	setColor("161616")
end

function setDrawColorToValueBoxText()
	setColor("9F9F9F")
end


--[[ text ]]--
function setDrawColorToText()
	setColor("878787")
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
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/ChordGun/src"

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
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/ChordGun/src"

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

  local imageWidth = 9
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
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/ChordGun/src"

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

  return self
end

function Label:drawRedOutline()
  setDrawColorToRed()
  gfx.rect(self.x, self.y, self.width, self.height, false)
end

function Label:drawText(text)

	setDrawColorToText()
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
end

function Label:update()
  --self:drawRedOutline()

  local text = self.getTextCallback()
  self:drawText(text)
end
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/ChordGun/src"

Header = {}
Header.__index = Header


local function getHeaderRadius()
	return s(5)
end

function Header:new(x, y, width, height, getTextCallback)

  local self = {}
  setmetatable(self, Header)

  self.x = x
  self.y = y
  self.width = width
  self.height = height
  self.getTextCallback = getTextCallback

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
end
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/ChordGun/src"

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
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/ChordGun/src"

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
	local stringWidth, stringHeight = gfx.measurestr(text)
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
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/ChordGun/src"

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

  local imageWidth = 9
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
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/ChordGun/src"

ChordButton = {}
ChordButton.__index = ChordButton


local currentlyHeldButton = nil

local holdModeEnabled = false

local lastPlayedChord = nil


local externalMidiNotes = {}
local lastProcessedMidiSignature = nil
local midiQueuePrimed = false
local internalNoteEvents = {}
local internalNoteTimeoutSeconds = 0.3

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
  suppressExternalMidiUntil = math.max(suppressExternalMidiUntil or 0, reaper.time_precise() + 0.05)
end

consumeInternalNoteEvent = function(noteNumber, isNoteOn)
  if not reaper.time_precise then return false end

  pruneInternalNoteEvents()
  for i = #internalNoteEvents, 1, -1 do
    local event = internalNoteEvents[i]
    if event.note == noteNumber and event.isNoteOn == (isNoteOn and true or false) then
      table.remove(internalNoteEvents, i)
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
  if devIdx >= 0 then
    return true
  end

  return devIdx == -1
end

local function processExternalMidiInput()
  if not reaper.MIDI_GetRecentInputEvent then return end




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
    local noteNumber = rawMessage:byte(2) or 0
    local velocity = rawMessage:byte(3) or 0
    local isPhysicalInput = isExternalDevice(event.devIdx)
    local isNoteOn = (command == 0x90 and velocity > 0)
    local isNoteOff = (command == 0x80) or (command == 0x90 and velocity == 0)
    if isPhysicalInput and (isNoteOn or isNoteOff) then
      if consumeInternalNoteEvent(noteNumber, isNoteOn) then

      elseif isNoteOn then
        externalMidiNotes[noteNumber] = true
      else
        externalMidiNotes[noteNumber] = nil
      end
    end
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
	addChordToProgression(self.scaleNoteIndex, self.chordTypeIndex, self.text, selectedProgressionSlot)
	

	setSelectedScaleNote(self.scaleNoteIndex)
	setSelectedChordType(self.scaleNoteIndex, self.chordTypeIndex)
	
	local root = scaleNotes[self.scaleNoteIndex]
	local octave = getOctave()
	local notes = getChordNotesArray(root, chord, octave)
	
	playScaleChord(notes)
	setNotesThatArePlaying(notes)
	updateChordText(root, chord, notes)
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
		stopAllNotesFromPlaying()
		currentlyHeldButton = nil
		lastPlayedChord = nil
	end
	

	if tooltipsEnabled and isHovering then
		local tooltip = "Click: Preview | Shift+Click: Insert | Alt+Click: Add to slot"
		

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

function SimpleButton:new(text, x, y, width, height, onClick, onRightClick, getTooltip, drawBorder)
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
	return self
end

function SimpleButton:draw()

  if self.drawBorder then
    setColor("999999")
    gfx.rect(self.x, self.y, self.width, self.height, false)

    gfx.rect(self.x+1, self.y+1, self.width-2, self.height-2, false)
  end
	

	if mouseIsHoveringOver(self) then
		setColor("FFD700")
	else
		setColor("CCCCCC")
	end
	
	local displayText = type(self.getText) == "function" and self.getText() or self.text
	local stringWidth, stringHeight = gfx.measurestr(displayText)
	gfx.x = self.x + ((self.width - stringWidth) / 2)
	gfx.y = self.y + ((self.height - stringHeight) / 2)
	gfx.drawstr(displayText)
	

	if tooltipsEnabled and mouseIsHoveringOver(self) and self.getTooltip then
		local tooltip = self.getTooltip()
		if tooltip then
			queueTooltip(tooltip, gfx.mouse_x, gfx.mouse_y)
		end
	end
end

function SimpleButton:update()
	self:draw()
	
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
    setColor("999999")
    gfx.rect(self.x, self.y, self.width, self.height, false)

    gfx.rect(self.x+1, self.y+1, self.width-2, self.height-2, false)
  end

	local isActive = self.getState()
	

	if isActive then
		setColor("FFD700")
	elseif mouseIsHoveringOver(self) then
		setColor("FFFFFF")
	else
		setColor("CCCCCC")
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
		setColor("999999")
		gfx.rect(self.x, self.y, self.width, self.height, false)

		gfx.rect(self.x+1, self.y+1, self.width-2, self.height-2, false)
	end


	local currentIndex = self.getCurrentIndex()
	local text = self.options[currentIndex] or "?"
	

	if mouseIsHoveringOver(self) then
		setColor("FFD700")
	else
		setColor("CCCCCC")
	end
	
	local stringWidth, stringHeight = gfx.measurestr(text)
	gfx.x = self.x + ((self.width - stringWidth) / 2)
	gfx.y = self.y + ((self.height - stringHeight) / 2)
	gfx.drawstr(text)
end

function CycleButton:update()
	self:draw()
	
	if mouseButtonIsNotPressedDown and mouseIsHoveringOver(self) and leftMouseButtonIsHeldDown() then
		mouseButtonIsNotPressedDown = false
		local currentIndex = self.getCurrentIndex()
		local nextIndex = (currentIndex % #self.options) + 1
		self.onCycle(nextIndex)
	end
end


function showHelpWindow()

	if helpWindowOpen then return end
	

	local scriptPath = debug.getinfo(1, "S").source:match("@?(.*)")
	local scriptDir = scriptPath:match("(.+)[/\\]")
	local helpScriptPath = scriptDir .. "/TK_ChordGun_Help.lua"
	

	reaper.SetExtState("TKChordGunHelp", "shouldOpen", "1", false)
	helpWindowOpen = true
	


	local cmdID = reaper.AddRemoveReaScript(true, 0, helpScriptPath, false)
	if cmdID and cmdID > 0 then
		reaper.Main_OnCommand(cmdID, 0)

	end
end


local helpWindowOpen = false


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
	reaper.SetExtState("TKChordGunFifthWheel", "uiScale", tostring(uiScale), false)
	

	local wheelScript = [[
	local notes = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
	local notesFlat = {"C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"}
	

	local orderFifths = {1, 8, 3, 10, 5, 12, 7, 2, 9, 4, 11, 6}
	local orderChromatic = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12}
	
	local useFlats = false
	local useChromatic = false
	

		local uiScale = tonumber(reaper.GetExtState("TKChordGunFifthWheel", "uiScale")) or 1.0
		

		local function s(size)
			return math.floor(size * uiScale + 0.5)
		end
		
	local baseW, baseH = 400, 400
	local windowW, windowH = s(baseW), s(baseH)
	local centerX, centerY = windowW/2, windowH/2
	local radius = s(140)
	local noteRadius = s(28)
	

	local savedX = tonumber(reaper.GetExtState("TKChordGunFifthWheel", "windowX")) or -1
	local savedY = tonumber(reaper.GetExtState("TKChordGunFifthWheel", "windowY")) or -1
	
	gfx.init("Circle of Fifths / Modes", windowW, windowH, 0, savedX, savedY)
	gfx.setfont(1, "Arial", s(16), string.byte('b'))	function drawWheel()

		gfx.set(0.15, 0.15, 0.15, 1)
		gfx.rect(0, 0, windowW, windowH, 1)
		

		local noteOrder = useChromatic and orderChromatic or orderFifths
		

		local toggleText = useFlats and "b" or "#"
		gfx.setfont(2, "Arial", s(16), string.byte('b'))
		local toggleW = gfx.measurestr(toggleText)
		local toggleX = s(10)
		local toggleY = s(10)
		local toggleH = s(24)
		local toggleButtonX = toggleX
		local toggleButtonY = toggleY
		local toggleButtonW = s(24)
		

		gfx.set(0.25, 0.25, 0.25, 1)
		gfx.rect(toggleButtonX, toggleButtonY, toggleButtonW, toggleH, 1)
		

		gfx.set(0.5, 0.5, 0.5, 1)
		gfx.rect(toggleButtonX, toggleButtonY, toggleButtonW, toggleH, 0)
		

		gfx.set(1, 1, 1, 1)
		gfx.x = toggleButtonX + (toggleButtonW - toggleW) / 2
		gfx.y = toggleButtonY + (toggleH - s(16)) / 2
		gfx.drawstr(toggleText)
		

		local orderText = useChromatic and "Chromatic" or "Fifths"
		local orderW = gfx.measurestr(orderText)
		local orderButtonW = orderW + s(20)
		local orderButtonX = windowW - orderButtonW - s(10)
		
		gfx.set(0.25, 0.25, 0.25, 1)
		gfx.rect(orderButtonX, toggleButtonY, orderButtonW, toggleH, 1)
		gfx.set(0.5, 0.5, 0.5, 1)
		gfx.rect(orderButtonX, toggleButtonY, orderButtonW, toggleH, 0)
		gfx.set(1, 1, 1, 1)
		gfx.x = orderButtonX + (orderButtonW - orderW) / 2
		gfx.y = toggleButtonY + (toggleH - s(16)) / 2
		gfx.drawstr(orderText)
		

		local displayNotes = useFlats and notesFlat or notes
		

		local currentTonic = tonumber(reaper.GetExtState("TKChordGunFifthWheel", "tonic")) or 1
		local isCustomScale = reaper.GetExtState("TKChordGunFifthWheel", "isCustom") == "1"
		local scalePattern = {}
		for i = 1, 12 do
			scalePattern[i] = reaper.GetExtState("TKChordGunFifthWheel", "scale" .. i) == "1"
		end
		

		local symmetryPoints = {}
		if useChromatic then
			local activeNotes = {}
			for i = 1, 12 do
				if scalePattern[i] then table.insert(activeNotes, i) end
			end
			
			if #activeNotes > 0 then
				for shift = 1, 11 do
					local matches = 0
					for _, noteIdx in ipairs(activeNotes) do
						local shiftedIdx = ((noteIdx - 1 + shift) % 12) + 1
						if scalePattern[shiftedIdx] then
							matches = matches + 1
						end
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
			
			if dist == 0 then
				return {1.0, 0.84, 0.0}
			elseif dist == 1 then

				local clockwise = (diff == 1) or (diff == -11)
				if clockwise then
					return {0.4, 0.85, 0.4}
				else
					return {0.9, 0.4, 0.8}
				end
			elseif dist == 2 then
				return {0.5, 0.9, 0.9}
			elseif dist == 3 then
				return {1.0, 0.6, 0.2}
			elseif dist == 4 then
				return {0.85, 0.5, 0.35}
			else
				return {0.5, 0.3, 0.3}
			end
		end			gfx.setfont(1, "Arial", 16, string.byte('b'))
			


			gfx.set(0.5, 0.5, 0.5, 0.3)
			

			local activeIndices = {}
			for i = 1, 12 do
				local noteIndex = noteOrder[i]
				if scalePattern[noteIndex] then
					table.insert(activeIndices, i)
				end
			end
			

			if #activeIndices > 1 then
				gfx.set(1, 1, 1, 0.15)
				for i = 1, #activeIndices do
					local idx1 = activeIndices[i]
					local idx2 = activeIndices[(i % #activeIndices) + 1]
					
					local angle1 = (idx1 - 1) * (math.pi * 2 / 12) - (math.pi / 2)
					local angle2 = (idx2 - 1) * (math.pi * 2 / 12) - (math.pi / 2)
					
					local x1 = centerX + math.cos(angle1) * radius
					local y1 = centerY + math.sin(angle1) * radius
					local x2 = centerX + math.cos(angle2) * radius
					local y2 = centerY + math.sin(angle2) * radius
					
					gfx.line(x1, y1, x2, y2, 1)
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
			
			if useChromatic and not isInScale then
				currentNoteRadius = s(5)
				drawText = false
			end
			

	local color
	if isCustomScale or useChromatic then

		if isCurrentTonic then
			color = {1.0, 0.84, 0.0}
		elseif isInScale then
			color = {0.5, 0.75, 0.9}
		else
			color = {0.2, 0.2, 0.2}
		end
	else

		if isCurrentTonic then
			color = {1.0, 0.84, 0.0}
		elseif isInScale then
			color = getHarmonicDistanceColor(noteIndex, currentTonic)
			color[1] = math.min(1.0, color[1] * 1.2)
			color[2] = math.min(1.0, color[2] * 1.2)
			color[3] = math.min(1.0, color[3] * 1.2)
		else
			color = {0.25, 0.25, 0.25}
		end
	end
	gfx.set(color[1], color[2], color[3], 1)
	gfx.circle(x, y, currentNoteRadius, 1)
	if isCurrentTonic then
		gfx.set(1.0, 1.0, 1.0, 1)
		gfx.circle(x, y, currentNoteRadius, 0)
		gfx.circle(x, y, currentNoteRadius-1, 0)
	elseif isInScale then
		gfx.set(1.0, 1.0, 1.0, 1)
		gfx.circle(x, y, currentNoteRadius, 0)
		gfx.circle(x, y, currentNoteRadius-1, 0)
		if isCustomScale or useChromatic then

		else
			gfx.circle(x, y, currentNoteRadius-2, 0)
		end
	else
		gfx.set(0.4, 0.4, 0.4, 1)
		gfx.circle(x, y, currentNoteRadius, 0)
	end
	

	if isSymmetryPoint and not isCurrentTonic then
		gfx.set(1.0, 0.84, 0.0, 0.6)
		gfx.circle(x, y, currentNoteRadius + s(4), 0)
		gfx.circle(x, y, currentNoteRadius + s(5), 0)
		gfx.circle(x, y, currentNoteRadius + s(6), 0)
		gfx.circle(x, y, currentNoteRadius + s(7), 0)
	end
	

			if drawText then
				gfx.set(0, 0, 0, 1)
				gfx.setfont(1, "Arial", s(16), string.byte('b'))
				local noteName = displayNotes[noteIndex]
				local textW, textH = gfx.measurestr(noteName)
				gfx.x = x - textW / 2
				gfx.y = y - textH / 2
				

				if not useChromatic then
					gfx.y = y - textH / 2 - s(6)
				end
				
				gfx.drawstr(noteName)
				

				if not useChromatic then
					local minorNoteIndex = ((noteIndex + 8) % 12) + 1
					local minorName = displayNotes[minorNoteIndex] .. "m"
					gfx.setfont(4, "Arial", s(13))
					local minorW, minorH = gfx.measurestr(minorName)
					gfx.x = x - minorW / 2
					gfx.y = y - minorH / 2 + s(8)
					gfx.set(0, 0, 0, 1)
					gfx.drawstr(minorName)
				end
			end
		end
	

	gfx.setfont(5, "Arial", s(13))
	local legendY = centerY - s(20)
	
	if useChromatic then

		gfx.set(1, 1, 1, 1)
		local titleText = "Chromatic Order"
		local titleW = gfx.measurestr(titleText)
		gfx.x = centerX - titleW / 2
		gfx.y = legendY
		gfx.drawstr(titleText)
		
		gfx.set(0.7, 0.7, 0.7, 1)
		local subText = "Visualizes symmetry"
		local subW = gfx.measurestr(subText)
		gfx.x = centerX - subW / 2
		gfx.y = legendY + s(18)
		gfx.drawstr(subText)
		

		gfx.set(1.0, 0.84, 0.0, 0.8)
		local haloText = "Halo: Equivalent Tonic"
		local haloW = gfx.measurestr(haloText)
		gfx.x = centerX - haloW / 2
		gfx.y = legendY + s(36)
		gfx.drawstr(haloText)
	else


		gfx.set(1, 1, 1, 1)
		local titleText = "Color Legend:"
		local titleW = gfx.measurestr(titleText)
		gfx.x = centerX - titleW / 2
		gfx.y = legendY - s(60)
		gfx.drawstr(titleText)
		
		local startY = legendY - s(40)
		local lineHeight = s(18)
		

		local legendItems
		if isCustomScale then
			legendItems = {
				{{1.0, 0.84, 0.0}, "Tonic (root note)"},
				{{0.5, 0.75, 0.9}, "In scale"},
				{{0.2, 0.2, 0.2}, "Out of scale"}
			}
		else
			legendItems = {
				{{1.0, 0.84, 0.0}, "Tonic"},
				{{0.4, 0.85, 0.4}, "+1 Fifth up"},
				{{0.9, 0.4, 0.8}, "-1 Fifth down"},
				{{0.5, 0.9, 0.9}, "+2 Fifths up"},
				{{1.0, 0.6, 0.2}, "+3 Fifths up"},
				{{0.85, 0.5, 0.35}, "+4 Fifths up"},
				{{0.5, 0.3, 0.3}, "+5/6 Fifths (Tritone)"}
			}
		end
		
		for i, item in ipairs(legendItems) do
			local color = item[1]
			local label = item[2]
			

			gfx.set(color[1], color[2], color[3], 1)
			local boxSize = s(12)
			local boxX = centerX - s(50)
			gfx.rect(boxX, startY, boxSize, boxSize, 1)
			

			gfx.set(1, 1, 1, 1)
			gfx.x = boxX + boxSize + s(6)
			gfx.y = startY
			gfx.drawstr(label)
			
			startY = startY + lineHeight
		end
	end
	

		gfx.setfont(3, "Arial", s(18))
		gfx.set(0.7, 0.7, 0.7, 1)
		local instr = "Click a note to change tonic â€¢ ESC to close"
		local instrW = gfx.measurestr(instr)
		gfx.x = (windowW - instrW) / 2
		gfx.y = windowH - s(20)
	gfx.drawstr(instr)
end
		function main()
		drawWheel()
		gfx.update()
		

	local forceClose = reaper.GetExtState("TKChordGunFifthWheel", "forceClose")
	if forceClose == "1" then
		reaper.SetExtState("TKChordGunFifthWheel", "forceClose", "0", false)
		reaper.SetExtState("TKChordGunFifthWheel", "closed", "1", false)
		return
	end
	
	local char = gfx.getchar()
	if char == 27 or char == -1 then

		local dockState, posX, posY = gfx.dock(-1, 0, 0, 0, 0)
		reaper.SetExtState("TKChordGunFifthWheel", "windowX", tostring(posX), true)
		reaper.SetExtState("TKChordGunFifthWheel", "windowY", tostring(posY), true)
		reaper.SetExtState("TKChordGunFifthWheel", "closed", "1", false)
		return
	end
		if gfx.mouse_cap & 1 == 1 then
			local mx = gfx.mouse_x
			local my = gfx.mouse_y
			

			if not mouseWasDown then

				local toggleButtonX = s(10)
				local toggleButtonY = s(10)
				local toggleButtonW = s(24)
				local toggleButtonH = s(24)
				

				local orderText = useChromatic and "Chromatic" or "Fifths"
				gfx.setfont(2, "Arial", s(16), string.byte('b'))
				local orderW = gfx.measurestr(orderText)
				local orderButtonW = orderW + s(20)
				local orderButtonX = windowW - orderButtonW - s(10)
				
				if mx >= toggleButtonX and mx <= toggleButtonX + toggleButtonW and
				   my >= toggleButtonY and my <= toggleButtonY + toggleButtonH then
					useFlats = not useFlats
				elseif mx >= orderButtonX and mx <= orderButtonX + orderButtonW and
				       my >= toggleButtonY and my <= toggleButtonY + toggleButtonH then
					useChromatic = not useChromatic
				else

					local noteOrder = useChromatic and orderChromatic or orderFifths
					for i = 1, 12 do
						local angle = (i - 1) * (math.pi * 2 / 12) - (math.pi / 2)
						local noteIndex = noteOrder[i]
						local x = centerX + math.cos(angle) * radius
						local y = centerY + math.sin(angle) * radius
						
						local dist = math.sqrt((mx - x)^2 + (my - y)^2)
						if dist < noteRadius then
							reaper.SetExtState("TKChordGunFifthWheel", "selectedTonic", tostring(noteIndex), false)
							break
						end
					end
				end
				mouseWasDown = true
			end
		else
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
		

		local currentTonic = getScaleTonicNote()
		local currentScale = scales[getScaleType()]
		local isCustomScale = currentScale.isCustom == true
		
		reaper.SetExtState("TKChordGunFifthWheel", "tonic", tostring(currentTonic), false)
		reaper.SetExtState("TKChordGunFifthWheel", "closed", "0", false)
		reaper.SetExtState("TKChordGunFifthWheel", "selectedTonic", "0", false)
		reaper.SetExtState("TKChordGunFifthWheel", "isCustom", isCustomScale and "1" or "0", false)
		
		for i = 1, 12 do
			local inScale = scalePattern and scalePattern[i] or false
			reaper.SetExtState("TKChordGunFifthWheel", "scale" .. i, inScale and "1" or "0", false)
		end
		

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
		reaper.SetExtState("TKChordGunFifthWheel", "tonic", tostring(currentTonic), false)
		reaper.SetExtState("TKChordGunFifthWheel", "isCustom", isCustomScale and "1" or "0", false)
		for i = 1, 12 do
			local inScale = scalePattern and scalePattern[i] or false
			reaper.SetExtState("TKChordGunFifthWheel", "scale" .. i, inScale and "1" or "0", false)
		end
		lastSyncedTonic = currentTonic
		lastSyncedScale = scaleHash
	end
	

	local closed = reaper.GetExtState("TKChordGunFifthWheel", "closed")
	if closed == "1" then
		fifthWheelWindowOpen = false
		reaper.SetExtState("TKChordGunFifthWheel", "closed", "0", false)
		lastSyncedTonic = nil
		lastSyncedScale = nil
		return
	end
	

	local selectedTonic = tonumber(reaper.GetExtState("TKChordGunFifthWheel", "selectedTonic"))
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
		reaper.SetExtState("TKChordGunFifthWheel", "isCustom", updatedIsCustom and "1" or "0", false)
		
		for i = 1, 12 do
			local inScale = scalePattern and scalePattern[i] or false
			reaper.SetExtState("TKChordGunFifthWheel", "scale" .. i, inScale and "1" or "0", false)
		end
		reaper.SetExtState("TKChordGunFifthWheel", "tonic", tostring(selectedTonic), false)
		reaper.SetExtState("TKChordGunFifthWheel", "selectedTonic", "0", false)
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

function ProgressionSlots:update()
	local slotWidth = (self.width - s(14)) / 8
	local slotHeight = self.height
	

	for i = 1, maxProgressionSlots do
		local x = self.x + ((i - 1) * slotWidth) + ((i - 1) * s(2))
		local y = self.y
		

		local isHovering = gfx.mouse_x >= x and gfx.mouse_x <= x + slotWidth and
		                   gfx.mouse_y >= y and gfx.mouse_y <= y + slotHeight
		

		local bgColor = {0.15, 0.15, 0.15}
		if currentProgressionIndex == i and progressionPlaying then
			bgColor = {0.2, 0.4, 0.6}
		elseif selectedProgressionSlot == i then
			bgColor = {0.3, 0.5, 0.3}
		elseif isHovering then
			bgColor = {0.2, 0.2, 0.2}
		end
		

		gfx.set(bgColor[1], bgColor[2], bgColor[3], 1)
		gfx.rect(x, y, slotWidth, slotHeight, true)
		

		if selectedProgressionSlot == i then
			gfx.set(0.5, 0.7, 0.5, 1)
			gfx.rect(x, y, slotWidth, slotHeight, false)
			gfx.rect(x+1, y+1, slotWidth-2, slotHeight-2, false)
		else
			gfx.set(0.3, 0.3, 0.3, 1)
			gfx.rect(x, y, slotWidth, slotHeight, false)
		end
		

		if i == progressionLength then
			gfx.set(1, 0.6, 0, 1)
			gfx.rect(x + slotWidth - s(3), y, s(3), slotHeight, true)
		end
		

    if chordProgression[i] then

      gfx.set(1, 1, 1, 1)
      gfx.setfont(1, "Arial", fontSize(13))
			local textW, textH = gfx.measurestr(chordProgression[i].text)
			gfx.x = x + (slotWidth - textW) / 2
			gfx.y = y + s(5)
			gfx.drawstr(chordProgression[i].text)
			

			local beats = chordProgression[i].beats or 1
			local repeats = chordProgression[i].repeats or 1
			local infoText = beats .. "b"
			if repeats > 1 then
				infoText = infoText .. " x" .. repeats
			end
      gfx.set(0.7, 0.7, 0.7, 1)
      gfx.setfont(1, "Arial", fontSize(10))
			local infoW, infoH = gfx.measurestr(infoText)
			gfx.x = x + (slotWidth - infoW) / 2
			gfx.y = y + slotHeight - infoH - s(3)
			gfx.drawstr(infoText)
    else

      gfx.set(0.4, 0.4, 0.4, 1)
      gfx.setfont(1, "Arial", fontSize(12))
			local num = tostring(i)
			local textW, textH = gfx.measurestr(num)
			gfx.x = x + (slotWidth - textW) / 2
			gfx.y = y + (slotHeight - textH) / 2
			gfx.drawstr(num)
		end
		

		if mouseButtonIsNotPressedDown and isHovering and gfx.mouse_cap & 1 == 1 and shiftModifierIsHeldDown() then
			progressionLength = i
			mouseButtonIsNotPressedDown = false

		elseif mouseButtonIsNotPressedDown and chordProgression[i] and isHovering and gfx.mouse_cap & 1 == 1 and ctrlModifierIsHeldDown() then
			local currentBeats = chordProgression[i].beats or 1
			local currentRepeats = chordProgression[i].repeats or 1
			
			local retval, userInput = reaper.GetUserInputs("Slot " .. i .. " Settings", 2, 
				"Beats (1/2/4/8):,Repeats (1-4):,extrawidth=100", 
				currentBeats .. "," .. currentRepeats)
			
			if retval then
				local beats, repeats = userInput:match("([^,]+),([^,]+)")
				beats = tonumber(beats)
				repeats = tonumber(repeats)
				

				if beats and (beats == 1 or beats == 2 or beats == 4 or beats == 8) then
					chordProgression[i].beats = beats
				end
				

				if repeats and repeats >= 1 and repeats <= 4 then
					chordProgression[i].repeats = math.floor(repeats)
				end
			end
			mouseButtonIsNotPressedDown = false

		elseif mouseButtonIsNotPressedDown and chordProgression[i] and isHovering and gfx.mouse_cap & 1 == 1 and not altModifierIsHeldDown() and not shiftModifierIsHeldDown() and not ctrlModifierIsHeldDown() then

			selectedProgressionSlot = i

			playChordFromSlot(i)
			mouseButtonIsNotPressedDown = false

		elseif mouseButtonIsNotPressedDown and not chordProgression[i] and isHovering and gfx.mouse_cap & 1 == 1 and not altModifierIsHeldDown() and not shiftModifierIsHeldDown() and not ctrlModifierIsHeldDown() then
			if selectedProgressionSlot == i then

				selectedProgressionSlot = nil
			else

				selectedProgressionSlot = i
			end
			mouseButtonIsNotPressedDown = false
		end
		

		if mouseButtonIsNotPressedDown and chordProgression[i] and isHovering then
			if gfx.mouse_cap & 2 == 2 then
				removeChordFromProgression(i)
				mouseButtonIsNotPressedDown = false
			end
		end
		

		if tooltipsEnabled and isHovering then
			local tooltip
			if chordProgression[i] then
				tooltip = "Click: Preview chord | Shift+Click: Set loop end | Ctrl+Click: Edit beats/repeats | Right-Click: Clear slot"
			else
				tooltip = "Click: Select slot for chord assignment | Shift+Click: Set loop endpoint"
			end
			queueTooltip(tooltip, gfx.mouse_x, gfx.mouse_y)
		end
	end
end

function PianoKeyboard:getStartNote()

	local currentOctave = getOctave()
	return (currentOctave * 12) + 12
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
			local root = scaleNotes[selectedScaleNote]
			local chord = scaleChords[selectedScaleNote][selectedChordType]
			local octave = getOctave()
			

			local chordPattern = chord["pattern"]
			for n = 0, #chordPattern-1 do
				if chordPattern:sub(n+1, n+1) == '1' then
					local noteValue = root + n + ((octave+1) * 12) - 1
					table.insert(activeNotes, noteValue)
				end
			end
			

			activeNotes = applyInversion(activeNotes)
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
    setColor("4DA6FF")
  elseif inScale then
		setColor("F0F0F0")
	else
		setColor("C0C0C0")
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
          noteName = noteName .. "â†’" .. mappedNoteName
        end
      end
    end
  end
  
  gfx.setfont(1, "Arial", fontSize(14))
	local stringWidth, stringHeight = gfx.measurestr(noteName)
	

  if isActive then
		setColor("000000")
  elseif isExternalActive then
    setColor("FFFFFF")
	else
		setColor("333333")
	end
	
	gfx.x = x + (w - stringWidth) / 2
	gfx.y = y + h - stringHeight - s(4)
  gfx.drawstr(noteName)


  if isCKey then
    local octaveLabel = tostring(getOctave() + (octaveIndex or 0))
    gfx.setfont(1, "Arial", fontSize(14))
    if isActive then
      setColor("000000")
    elseif isExternalActive then
      setColor("FFFFFF")
    else
      setColor("555555")
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
    setColor("4DA6FF")
  elseif inScale then
		setColor("1A1A1A")
	else
		setColor("606060")
	end
	gfx.rect(x, y, w, h, true)
	

	setColor("000000")
	gfx.rect(x, y, w, h, false)
	

  local noteName = notes[noteForScale]
  gfx.setfont(1, "Arial", fontSize(12))
	local stringWidth, stringHeight = gfx.measurestr(noteName)
	

  if isActive then
		setColor("000000")
  elseif isExternalActive then
    setColor("FFFFFF")
	else
		setColor("FFFFFF")
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

inputCharacters["ESC"] = 27

inputCharacters["LEFTARROW"] = 1818584692
inputCharacters["RIGHTARROW"] = 1919379572
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/ChordGun/src"


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

function handleInput()

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

	if inputCharacter == inputCharacters["0"] or middleMouseButtonIsHeldDown() then
		stopAllNotesFromPlaying()
	end

	--


	local numberKeys = {"1", "2", "3", "4", "5", "6", "7", "8", "9"}
	for i = 1, math.min(#scaleNotes, 9) do
		if inputCharacter == inputCharacters[numberKeys[i]] then
			previewScaleChordAction(i)
		end
	end

	--


	local shiftNumberKeys = {"!", "@", "#", "$", "%", "^", "&", "*", "("}
	for i = 1, math.min(#scaleNotes, 9) do
		if inputCharacter == inputCharacters[shiftNumberKeys[i]] then
			scaleChordAction(i)
		end
	end

	--


	local qwertyKeys = {"q", "w", "e", "r", "t", "y", "u", "i", "o"}
	for i = 1, math.min(#scaleNotes, 9) do
		if inputCharacter == inputCharacters[qwertyKeys[i]] then
			previewHigherScaleNoteAction(i)
		end
	end

	--


	local asdfKeys = {"a", "s", "d", "f", "g", "h", "j", "k", "l"}
	for i = 1, math.min(#scaleNotes, 9) do
		if inputCharacter == inputCharacters[asdfKeys[i]] then
			previewScaleNoteAction(i)
		end
	end

	--


	local zxcvKeys = {"z", "x", "c", "v", "b", "n", "m", ",", "."}
	for i = 1, math.min(#scaleNotes, 9) do
		if inputCharacter == inputCharacters[zxcvKeys[i]] then
			previewLowerScaleNoteAction(i)
		end
	end



	--


	local QWERTYKeys = {"Q", "W", "E", "R", "T", "Y", "U", "I", "O"}
	for i = 1, math.min(#scaleNotes, 9) do
		if inputCharacter == inputCharacters[QWERTYKeys[i]] then
			higherScaleNoteAction(i)
		end
	end

	--


	local ASDFKeys = {"A", "S", "D", "F", "G", "H", "J", "K", "L"}
	for i = 1, math.min(#scaleNotes, 9) do
		if inputCharacter == inputCharacters[ASDFKeys[i]] then
			scaleNoteAction(i)
		end
	end

	--


	local ZXCVKeys = {"Z", "X", "C", "V", "B", "N", "M", "<", ">"}
	for i = 1, math.min(#scaleNotes, 9) do
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
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/ChordGun/src"

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
  

  if interfaceWidth < minWidth then
    self.width = minWidth
  else
    self.width = interfaceWidth
  end
  
  if interfaceHeight < minHeight then
    self.height = minHeight
  else
    self.height = interfaceHeight
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
	

	if gfx.w < minWidth then
		self.width = minWidth
	else
		self.width = gfx.w
	end
	
	if gfx.h < minHeight then
		self.height = minHeight
	else
		self.height = gfx.h
	end
	
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

	gfx.clear = reaper.ColorToNative(36, 36, 36)

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

function Interface:addHeader(headerText, x, y, width, height, getTextCallback)

	local header = Header:new(headerText, x, y, width, height, getTextCallback)
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

function Interface:addSimpleButton(text, x, y, width, height, onClick, onRightClick, getTooltip, drawBorder)

	local button = SimpleButton:new(text, x, y, width, height, onClick, onRightClick, getTooltip, drawBorder)
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

  for _, element in pairs(self.elements) do
    applyDefaultFont()
    element:update()
  end
	

	renderPendingTooltips()
end

function Interface:update()

  processExternalMidiInput()
	self:updateElements()
	gfx.update()
	

	updateProgressionPlayback()

	if not mouseButtonIsNotPressedDown and leftMouseButtonIsNotHeldDown() then
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

local workingDirectory = reaper.GetResourcePath() .. "/Scripts/ChordGun/src"

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

function Interface:addTopFrame()

	local keySelectionFrameHeight = s(25)
	self.keySelectionFrameHeight = keySelectionFrameHeight
	local xMargin = s(8)
	local yMargin = s(8)
	local xPadding = s(16)
	local yPadding = s(5)
	local horizontalMargin = s(8)
	local scaleTonicNoteWidth = s(50)
	local scaleSystemWidth = s(100)
	local scaleTypeWidth = s(130)
	local octaveValueBoxWidth = s(55)

	self:addFrame(xMargin+dockerXPadding, yMargin, self.width - 2 * xMargin, keySelectionFrameHeight)
  self:addScaleLabel(xMargin, yMargin, xPadding, yPadding)
	self:addScaleTonicNoteDropdown(xMargin, yMargin, xPadding, yPadding, horizontalMargin, scaleTonicNoteWidth)
	self:addScaleSystemDropdown(xMargin, yMargin, xPadding, yPadding, horizontalMargin, scaleTonicNoteWidth, scaleSystemWidth)
	self:addScaleTypeDropdown(xMargin, yMargin, xPadding, yPadding, horizontalMargin, scaleTonicNoteWidth, scaleSystemWidth, scaleTypeWidth)
	self:addScaleNotesTextLabel(xMargin, yMargin, xPadding, yPadding, horizontalMargin, scaleTonicNoteWidth, scaleSystemWidth, scaleTypeWidth)
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
  return sx(8)
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
    return "Click: Cycle filter mode (Off â†’ Filter â†’ Remap)\nFilter: blocks non-scale notes\nRemap: maps white keys to scale notes"
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
  self:addCycleButton(
    buttonX,
    yPos,
    buttonWidth,
    buttonHeight,
    noteLengthLabels,
    function() return getNoteLengthIndex() end,
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

			reaper.SetExtState("TKChordGunFifthWheel", "closed", "1", false)
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
    return reaper.GetExtState("TK_ChordGun", "useMonospaceFont") == "1"
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
             "This JSFX enables the Filter and Remap modes for live MIDI input."
  end
  
  self:addSimpleButton("Setup", buttonXpos+dockerXPadding, buttonYpos, buttonWidth, buttonHeight, onClick, nil, getTooltip)
end

function Interface:addPianoKeyboard(xMargin, yMargin, xPadding, yPadding, headerHeight)

	local pianoWidth = self.width - 2 * xMargin - 2 * xPadding
	local pianoHeight = sy(70)
	local pianoXpos = xMargin + xPadding
	


	local buttonHeight = sy(38)
	local innerSpacing = sx(2)
	local numChordButtons = #chords
	local pianoYpos = yMargin + yPadding + headerHeight + (numChordButtons * buttonHeight) + (numChordButtons * innerSpacing) - sy(3) + sy(6)
	



	local currentOctave = getOctave()
	local startNote = (currentOctave * 12) + 12
	
	self:addPiano(pianoXpos+dockerXPadding, pianoYpos, pianoWidth, pianoHeight, startNote, 2)
end

function Interface:addProgressionSlots(xMargin, yMargin, xPadding, yPadding, headerHeight)

	local slotWidth = self.width - 2 * xMargin - 2 * xPadding
  local slotHeight = sy(40)
	local slotXpos = xMargin + xPadding
	

	local buttonHeight = sy(38)
	local innerSpacing = sx(2)
	local numChordButtons = #chords
	local pianoHeight = sy(70)
	local pianoYpos = yMargin + yPadding + headerHeight + (numChordButtons * buttonHeight) + (numChordButtons * innerSpacing) - sy(3) + sy(6)
	local slotYpos = pianoYpos + pianoHeight + sy(8)
	
	local slots = ProgressionSlots:new(slotXpos + dockerXPadding, slotYpos, slotWidth, slotHeight)
	table.insert(self.elements, slots)
end

function Interface:addProgressionControls(xMargin, yMargin, xPadding, yPadding, headerHeight)

	local buttonWidth = sx(75)
	local buttonHeight = sy(24)
	local buttonXpos = xMargin + xPadding
  local buttonSpacing = sx(6)
	

	local buttonHeightChord = sy(38)
	local innerSpacing = sx(2)
	local numChordButtons = #chords
	local pianoHeight = sy(70)
  local slotHeight = sy(40)
	local pianoYpos = yMargin + yPadding + headerHeight + (numChordButtons * buttonHeightChord) + (numChordButtons * innerSpacing) - sy(3) + sy(6)
	local slotYpos = pianoYpos + pianoHeight + sy(8)
	local buttonYpos = slotYpos + slotHeight + sy(6)
	

  self:addSimpleButton(
    "Play",
		buttonXpos + dockerXPadding,
		buttonYpos,
		buttonWidth,
		buttonHeight,
		function() startProgressionPlayback() end,
		nil,
		function() return "Click: Start progression playback" end,
    true
	)
	

  self:addSimpleButton(
    "Stop",
    buttonXpos + dockerXPadding + buttonWidth + buttonSpacing,
		buttonYpos,
		buttonWidth,
		buttonHeight,
		function() stopProgressionPlayback() end,
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
		nil,
		function() return "Click: Load progression preset" end,
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
  local rightAlignX = buttonXpos + dockerXPadding + totalWidth - buttonWidth
  local leftOfRightAlignX = rightAlignX - buttonSpacing - buttonWidth
  
  local chordDisplayX = insertInlineX + buttonWidth + buttonSpacing
  local chordDisplayWidth = leftOfRightAlignX - chordDisplayX - buttonSpacing
  local chordDisplayHeight = (buttonHeight * 2) + s(8)
  
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
    

    setColor("4A4A4A")
    gfx.rect(x, y, w, h, false)
    
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
        setColor("4DA6FF")
      else
        setColor("FF8C00")
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
	


	


	


	

  local buttonYposRow2 = buttonYpos + buttonHeight + s(6)
  

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
  self:addSimpleButton("Setup", buttonXpos + dockerXPadding + buttonWidth + buttonSpacing, buttonYposRow2, buttonWidth, buttonHeight, onSetupClick, nil, function() return "Click: Add TK Scale Filter to selected track's Input FX" end, true)


  local bassOptions = {"Bass Off", "Bass -1", "Bass -2"}
  
  self:addCycleButton(
    buttonXpos + dockerXPadding + (buttonWidth + buttonSpacing) * 2,
    buttonYposRow2,
    buttonWidth,
    buttonHeight,
    bassOptions,
    function() return bassMode + 1 end,
    function(newIndex)
      bassMode = newIndex - 1
    end,
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
    buttonXpos + dockerXPadding + (buttonWidth + buttonSpacing) * 3,
    buttonYposRow2,
    buttonWidth,
    buttonHeight,
    function() generateMelodyFromProgression() end,
    onMelodyRightClick,
    function() return "Click: Generate Melody | Right-Click: Melody Settings" end,
    true
  )
  

  local getMonoState = function() return reaper.GetExtState("TK_ChordGun", "useMonospaceFont") == "1" end
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
  self:addToggleButton("Font", buttonXpos + dockerXPadding + (buttonWidth + buttonSpacing) * 4, buttonYposRow2, buttonWidth, buttonHeight, getMonoState, onMonoToggle, onFontRightClick, function() return "Toggle Monospace Font | Right-click: Set Font Scale" end, true)


  local getRatioState = function() return reaper.GetExtState("TK_ChordGun", "useFixedRatio") == "1" end
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

  self:addToggleButton("Ratio", buttonXpos + dockerXPadding + (buttonWidth + buttonSpacing) * 5, buttonYposRow2, buttonWidth, buttonHeight, getRatioState, onRatioToggle, onRatioRightClick, function() return "Toggle Fixed Aspect Ratio | Right-click: Set Window Size" end, true)


  local totalWidth = self.width - 2 * xMargin - 2 * xPadding
  




  
  local rightAlignX = buttonXpos + dockerXPadding + totalWidth - buttonWidth
  local leftOfRightAlignX = rightAlignX - buttonSpacing - buttonWidth
  
  self:addToggleButton(
    "Tooltip",
    leftOfRightAlignX,
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
    rightAlignX,
    buttonYpos,
    buttonWidth,
    buttonHeight,
    function() showHelpWindow() end,
    onHelpRightClick,
    function() return "Click: Show Help / Shortcuts | Right-Click: Links" end,
    true
  )
	

  local getCircleState = function() return fifthWheelWindowOpen end
  local onCircleToggle = function()
    if fifthWheelWindowOpen then
      reaper.SetExtState("TKChordGunFifthWheel", "closed", "1", false)
      fifthWheelWindowOpen = false
    else
      showFifthWheel()
    end
  end
  self:addToggleButton("Circle", leftOfRightAlignX, buttonYposRow2, buttonWidth, buttonHeight, getCircleState, onCircleToggle, nil, function() return "Toggle Circle of Fifths" end, true)
	

  self:addSimpleButton(
    function() return windowIsDocked() and "Undock" or "Dock" end,
		rightAlignX,
		buttonYposRow2,
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
	self:addDropdown(scaleSystemXpos+dockerXPadding, scaleSystemYpos, scaleSystemWidth, scaleSystemHeight, systemNames, currentSystemIndex, onScaleSystemSelection)
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
		table.insert(scaleNames, scale.name)
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
	octaveLabelWidth = gfx.measurestr(labelText) * (gfx.w / baseWidth)
	local labelYpos = yMargin+yPadding+s(1)
	local labelHeight = s(15)
  local contentRight = getTopFrameContentRight(xMargin)
  local spacing = s(6)
  local labelXpos = contentRight - octaveValueBoxWidth - spacing - octaveLabelWidth
	self:addLabel(labelXpos+dockerXPadding, labelYpos, octaveLabelWidth, labelHeight, function() return labelText end)
end

function Interface:addOctaveSelectorValueBox(yMargin, xMargin, xPadding, octaveValueBoxWidth)

  local contentRight = getTopFrameContentRight(xMargin)
  local pickerLeftShift = s(8)
  local valueBoxXPos = contentRight - octaveValueBoxWidth - pickerLeftShift
	local valueBoxYPos = yMargin + s(6)
	local valueBoxHeight = s(15)
	self:addOctaveValueBox(valueBoxXPos+dockerXPadding, valueBoxYPos, octaveValueBoxWidth, valueBoxHeight)
end
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/ChordGun/src"










local chordTextWidth = nil

function Interface:addBottomFrame()


	local xMargin = s(8)
	local yMargin = sy(8) + (self.keySelectionFrameHeight or sy(25)) + sy(6)
	local xPadding = sx(7)
	local yPadding = sy(30)
	local headerHeight = sy(25)
	local inversionLabelWidth = sx(80)
	local inversionValueBoxWidth = sx(55)

	local chordButtonsFrameHeight = self.height - yMargin
	self:addFrame(xMargin+dockerXPadding, yMargin, self.width - 2 * xMargin, chordButtonsFrameHeight)
  
  self:addHoldButton(xMargin, yMargin, xPadding)
  self:addKillButton(xMargin, yMargin, xPadding)
  self:addStrumButton(xMargin, yMargin, xPadding)
  local lenButtonX = topButtonXPos(xMargin, xPadding, 3)
  local lenButtonY = topButtonYPos(yMargin)
  self:addNoteLengthControl(lenButtonX, lenButtonY, {showLabel = false, buttonWidth = sx(75)})

  
  self:addPianoKeyboard(xMargin, yMargin, xPadding, yPadding, headerHeight)
  self:addProgressionSlots(xMargin, yMargin, xPadding, yPadding, headerHeight)
  self:addProgressionControls(xMargin, yMargin, xPadding, yPadding, headerHeight)
  self:addChordTextLabel(xMargin, yMargin, xPadding, inversionLabelWidth, inversionValueBoxWidth)
  self:addInversionLabel(xMargin, yMargin, xPadding)
  self:addInversionValueBox(xMargin, yMargin, xPadding, inversionLabelWidth)
  
  self:addHeaders(xMargin, yMargin, xPadding, yPadding, headerHeight)
	self:addChordButtons(xMargin, yMargin, xPadding, yPadding, headerHeight)
end

function Interface:addChordTextLabel(xMargin, yMargin, xPadding, inversionLabelWidth, inversionValueBoxWidth)

  local getChordTextCallback = function() return getChordText() end
  local chordTextXpos = xMargin + xPadding
  local chordTextYpos = yMargin + sy(4)
  chordTextWidth = self.width - 4 * xMargin - inversionLabelWidth - inversionValueBoxWidth - sx(6)
  local chordTextHeight = sy(24)
  self:addLabel(chordTextXpos+dockerXPadding, chordTextYpos, chordTextWidth, chordTextHeight, getChordTextCallback, {xOffset = sx(75)})
end

function Interface:addInversionLabel(xMargin, yMargin, xPadding)

  local inversionLabelText = "Inversion:"
  local inversionLabelXPos = xMargin + xPadding + chordTextWidth
  local inversionLabelYPos = yMargin + sy(4)
  local stringWidth, _ = gfx.measurestr(labelText)
  local inversionLabelTextHeight = sy(24)
  local inversionLabelWidth = sx(80)

  self:addLabel(inversionLabelXPos+dockerXPadding, inversionLabelYPos, inversionLabelWidth, inversionLabelTextHeight, function() return inversionLabelText end)
end

function Interface:addInversionValueBox(xMargin, yMargin, xPadding, inversionLabelWidth)

  local inversionValueBoxWidth = sx(55)
  local inversionValueBoxXPos = xMargin + xPadding + chordTextWidth + inversionLabelWidth + sx(2)
  local inversionValueBoxYPos = yMargin + sy(9)
  local inversionValueBoxHeight = sy(15)
  self:addChordInversionValueBox(inversionValueBoxXPos+dockerXPadding, inversionValueBoxYPos, inversionValueBoxWidth, inversionValueBoxHeight)
end

function Interface:addHeaders(xMargin, yMargin, xPadding, yPadding, headerHeight)
  
  for i = 1, #scaleNotes do

    local headerWidth = sx(104)
    local innerSpacing = sx(2)

    local headerXpos = xMargin+xPadding-sx(1) + headerWidth * (i-1) + innerSpacing * i
    local headerYpos = yMargin+yPadding
    self:addHeader(headerXpos+dockerXPadding, headerYpos, headerWidth, headerHeight, function() return getScaleDegreeHeader(i) end)
  end
end

function Interface:addChordButtons(xMargin, yMargin, xPadding, yPadding, headerHeight)

  local scaleNoteIndex = 1
  for note = getScaleTonicNote(), getScaleTonicNote() + 11 do

    if noteIsInScale(note) then

      for chordTypeIndex, chord in ipairs(scaleChords[scaleNoteIndex]) do

      	local text = getScaleNoteName(scaleNoteIndex) .. chord['display']

      	local buttonWidth = sx(104)
      	local buttonHeight = sy(38)
				local innerSpacing = sx(2)
      	
      	local xPos = xMargin + xPadding + buttonWidth * (scaleNoteIndex-1) + innerSpacing * scaleNoteIndex + dockerXPadding
      	local yPos = yMargin + yPadding + headerHeight + buttonHeight * (chordTypeIndex-1) + innerSpacing * (chordTypeIndex-1) - sy(3)
  
  			local numberOfChordsInScale = getNumberOfScaleChordsForScaleNoteIndex(scaleNoteIndex)

       	if chordTypeIndex > numberOfChordsInScale then
          local chordIsInScale = false
      		self:addChordButton(text, xPos, yPos, buttonWidth, buttonHeight, scaleNoteIndex, chordTypeIndex, chordIsInScale)
      	else
          local chordIsInScale = true
      		self:addChordButton(text, xPos, yPos, buttonWidth, buttonHeight, scaleNoteIndex, chordTypeIndex, chordIsInScale)
      	end     	
      end
      
      scaleNoteIndex = scaleNoteIndex + 1
    end
  end
end
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/ChordGun/src"


--clearConsoleWindow()

interfaceWidth = getInterfaceWidth()
interfaceHeight = getInterfaceHeight()

updateScaleData()

local interface = Interface:init("CHORDGUN (TK MOD)")
interface:startGui()

local function windowHasNotBeenClosed()
	return inputCharacter ~= -1
end

local function cleanup()

	if fifthWheelWindowOpen then
		reaper.SetExtState("TKChordGunFifthWheel", "forceClose", "1", false)
		fifthWheelWindowOpen = false
	end
	

	if helpWindowOpen then
		helpWindowOpen = false
		reaper.SetExtState("TKChordGunHelp", "closed", "0", false)
	end
end

local function main()

	if helpWindowOpen then
		local helpClosed = reaper.GetExtState("TKChordGunHelp", "closed")
		if helpClosed == "1" then
			helpWindowOpen = false
			reaper.SetExtState("TKChordGunHelp", "closed", "0", false)
		end
	end

	if gfx.w ~= interface.lastWidth or gfx.h ~= interface.lastHeight then

		if reaper.GetExtState("TK_ChordGun", "useFixedRatio") == "1" then
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

	handleInput()
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



--

--

--




--
--
--

