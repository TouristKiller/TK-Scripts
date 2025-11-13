-- @noindex

baseWidth = 775
baseHeight = 770

function s(value)
	if gfx.w == 0 or gfx.h == 0 then
		return value * 2.0
	end
	local scaleX = gfx.w / baseWidth
	local scaleY = gfx.h / baseHeight
	local scale = (scaleX + scaleY) / 2
	return value * scale
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
    name = 'flat fifth',
    code = 'flat5',
    display = '5-',
    pattern = '10000010'
  },
}

function mouseIsHoveringOver(element)

	local x = gfx.mouse_x
	local y = gfx.mouse_y

	local isInHorizontalRegion = (x >= element.x and x < element.x+element.width)
	local isInVerticalRegion = (y >= element.y and y < element.y+element.height)
	return isInHorizontalRegion and isInVerticalRegion
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
for i = 1, 7 do
  table.insert(defaultSelectedChordTypes, 1)
end

defaultInversionStates = {}
for i = 1, 7 do
  table.insert(defaultInversionStates, 0)
end

defaultScaleNoteNames = {'C', 'D', 'E', 'F', 'G', 'A', 'B'}
defaultScaleDegreeHeaders = {'I', 'ii', 'iii', 'IV', 'V', 'vi', 'viio'}

defaultNotesThatArePlaying = {}
defaultDockState = 0
defaultWindowShouldBeDocked = tostring(false)

interfaceWidth = baseWidth * 2.0
interfaceHeight = baseHeight * 2.0

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
local uiScaleIndexKey = "uiScaleIndex"
local interfaceWidthKey = "interfaceWidth"
local interfaceHeightKey = "interfaceHeight"

-- Strum mode variables (global scope zodat ze overal toegankelijk zijn)
local strumEnabled = false
local strumDelayMs = 80  -- Milliseconds between each note in strum

-- Chord Progression variables
local chordProgression = {}  -- Array van {scaleNoteIndex, chordTypeIndex, text, beats, repeats}
local maxProgressionSlots = 8
local progressionPlaying = false
local currentProgressionIndex = 0
local currentProgressionRepeat = 0  -- Current repeat count for active slot
local progressionBeatsPerChord = 1  -- Beats per chord (1, 2, or 4)
local progressionLastBeatTime = 0
local selectedProgressionSlot = nil  -- Tracks which slot is selected for editing
local progressionLength = 8  -- How many slots to loop (1-8)

--

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

--

local function getTableFromString(arg)

  local output = {}

  for match in arg:gmatch("([^,%s]+)") do
    output[#output + 1] = match
  end

  return output
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
  return tonumber(temp[index])
end

function setChordInversionState(index, arg)

  local temp = getChordInversionStates()
  temp[index] = arg
  setTableValue(chordInversionStatesKey, temp)
end

--

function resetSelectedChordTypes()

  local numberOfSelectedChordTypes = 7

  for i = 1, numberOfSelectedChordTypes do
    setSelectedChordType(i, 1)
  end
end

function resetChordInversionStates()

  local numberOfChordInversionStates = 7

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
  return tonumber(getValue(interfaceWidthKey, baseWidth * 2.0))
end

function setInterfaceWidth(arg)
  setValue(interfaceWidthKey, arg)
end

function getInterfaceHeight()
  return tonumber(getValue(interfaceHeightKey, baseHeight * 2.0))
end

function setInterfaceHeight(arg)
  setValue(interfaceHeightKey, arg)
end

-- UI Scale functions
local uiScaleValues = {1.0, 1.5, 2.0}  -- Available scale values
local defaultUiScaleIndex = 3  -- Default to 2.0x (index 3)

function getUiScaleIndex()
  return tonumber(getValue(uiScaleIndexKey, defaultUiScaleIndex))
end

function setUiScaleIndex(index)
  setValue(uiScaleIndexKey, index)
end

function applyUiScale(index)
  local scale = uiScaleValues[index]
  interfaceWidth = baseWidth * scale
  interfaceHeight = baseHeight * scale
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

scales = {
  { name = "Major", pattern = "101011010101" },
  { name = "Natural Minor", pattern = "101101011010" },
  { name = "Harmonic Minor", pattern = "101101011001" },
  { name = "Melodic Minor", pattern = "101101010101" },
  { name = "Pentatonic", pattern = "101010010100" },
  { name = "Ionian", pattern = "101011010101" },
  { name = "Aeolian", pattern = "101101011010" },
  { name = "Dorian", pattern = "101101010110" },
  { name = "Mixolydian", pattern = "101011010110" },
  { name = "Phrygian", pattern = "110101011010" },
  { name = "Lydian", pattern = "101010110101" },
  { name = "Locrian", pattern = "110101101010" }
}
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/ChordGun/src"

notes = { 'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B' };
flatNotes = { 'C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B' };

function getScalePattern(scaleTonicNote, scale)

  local scalePatternString = scale['pattern']
  local scalePattern = {false,false,false,false,false,false,false,false,false,false,false}

  for i = 0, #scalePatternString do
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


  -- here is where you color the chord buttons differently
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

  local minorSymbols = {'i', 'ii', 'iii', 'iv', 'v', 'vi', 'vii'}
  local majorSymbols = {'I', 'II', 'III', 'IV', 'V', 'VI', 'VII'}
  local diminishedSymbol = 'o'
  local augmentedSymbol = '+'
  local sixthSymbol = '6'
  local seventhSymbol = '7'
  
  local i = 1
  for i = 1, #scaleNotes do
  
    local symbol = ""
   
    local chord = scaleChords[i][1]
    
    if string.match(chord.code, "major") or chord.code == '7' then
      symbol = majorSymbols[i]
    else
      symbol = minorSymbols[i]
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
  gfx.setfont(1, "Arial")       <-- default bitmap font does not support Unicode characters
  local degreeSymbolCharacter = 0x00B0  <-- this is the degree symbol for augmented chords,  "°"
  gfx.drawchar(degreeSymbolCharacter)

]]--

local tolerance = 0.000001

function activeMidiEditor()
  return reaper.MIDIEditor_GetActive()
end

function activeTake()
  return reaper.MIDIEditor_GetTake(activeMidiEditor())
end

function activeMediaItem()
  return reaper.GetMediaItemTake_Item(activeTake())
end

function activeTrack()
  return reaper.GetMediaItemTake_Track(activeTake())
end

function mediaItemStartPosition()
  return reaper.GetMediaItemInfo_Value(activeMediaItem(), "D_POSITION")
end

function mediaItemStartPositionPPQ()
  return reaper.MIDI_GetPPQPosFromProjTime(activeTake(), mediaItemStartPosition())
end

function mediaItemStartPositionQN()
  return reaper.MIDI_GetProjQNFromPPQPos(activeTake(), mediaItemStartPositionPPQ())
end

local function mediaItemLength()
  return reaper.GetMediaItemInfo_Value(activeMediaItem(), "D_LENGTH")
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

function getCursorPositionPPQ()
  return reaper.MIDI_GetPPQPosFromProjTime(activeTake(), cursorPosition())
end

local function getCursorPositionQN()
  return reaper.MIDI_GetProjQNFromPPQPos(activeTake(), getCursorPositionPPQ())
end

function getNoteLengthQN()

  local gridLength = reaper.MIDI_GetGrid(activeTake())
  return gridLength
end

function gridUnitLength()

  local gridLengthQN = reaper.MIDI_GetGrid(activeTake())
  local mediaItemPlusGridLengthPPQ = reaper.MIDI_GetPPQPosFromProjQN(activeTake(), mediaItemStartPositionQN() + gridLengthQN)
  local mediaItemPlusGridLength = reaper.MIDI_GetProjTimeFromPPQPos(activeTake(), mediaItemPlusGridLengthPPQ)
  return mediaItemPlusGridLength - mediaItemStartPosition()
end

function getMidiEndPositionPPQ()

  local startPosition = reaper.GetCursorPosition()
  local startPositionPPQ = reaper.MIDI_GetPPQPosFromProjTime(activeTake(), startPosition)
  local endPositionPPQ = reaper.MIDI_GetPPQPosFromProjTime(activeTake(), startPosition+gridUnitLength())
  return endPositionPPQ
end

function deselectAllNotes()

  local selectAllNotes = false
  reaper.MIDI_SelectAll(activeTake(), selectAllNotes)
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

  local _, numberOfNotes = reaper.MIDI_CountEvts(activeTake())
  return numberOfNotes
end

function deleteNote(noteIndex)

  reaper.MIDI_DeleteNote(activeTake(), noteIndex)
end

function thereAreNotesSelected()

  if activeTake() == nil then
    return false
  end

  local numberOfNotes = getNumberOfNotes()

  for noteIndex = 0, numberOfNotes-1 do

    local _, noteIsSelected = reaper.MIDI_GetNote(activeTake(), noteIndex)

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
end

function stopAllNotesFromPlaying()

  for midiNote = 0, 127 do

    local virtualKeyboardMode = 0
    local channel = getCurrentNoteChannel()
    local noteOffCommand = 0x80 + channel
    local velocity = 0

    reaper.StuffMIDIMessage(virtualKeyboardMode, noteOffCommand, midiNote, velocity)
  end
end

function stopNoteFromPlaying(midiNote)

  local virtualKeyboardMode = 0
  local channel = getCurrentNoteChannel()
  local noteOffCommand = 0x80 + channel
  local velocity = 0

  reaper.StuffMIDIMessage(virtualKeyboardMode, noteOffCommand, midiNote, velocity)
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
  local chord_ = chord
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
  
  return chordNotesArray
end
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/ChordGun/src"

function insertMidiNote(note, keepNotesSelected, selectedChord, noteIndex)

	local startPosition = getCursorPositionPPQ()
	
	-- Add strum offset if strum is enabled
	if strumEnabled then
		local ppq = reaper.MIDI_GetPPQPosFromProjQN(activeTake(), 0)
		local quarterNote = reaper.MIDI_GetProjQNFromPPQPos(activeTake(), ppq + 1)
		local oneBeatInPPQ = (ppq + 1) - ppq
		local strumOffsetPPQ = (strumDelayMs / 1000.0) * (oneBeatInPPQ * 2)  -- Approximate conversion
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
		
		-- Adjust end position for strum
		if strumEnabled then
			local ppq = reaper.MIDI_GetPPQPosFromProjQN(activeTake(), 0)
			local oneBeatInPPQ = (ppq + 1) - ppq
			local strumOffsetPPQ = (strumDelayMs / 1000.0) * (oneBeatInPPQ * 2)
			endPosition = endPosition + ((noteIndex - 1) * strumOffsetPPQ)
		end
		
	else
		endPosition = getMidiEndPositionPPQ()
		
		-- Adjust end position for strum
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
    -- Strum mode: play notes with delay between each note
    local delaySeconds = strumDelayMs / 1000.0
    
    for noteIndex = 1, #chordNotesArray do
      playMidiNote(chordNotesArray[noteIndex])
      
      -- Wait before playing next note (except after last note)
      if noteIndex < #chordNotesArray then
        local startTime = reaper.time_precise()
        local targetTime = startTime + delaySeconds
        
        -- Busy wait for precise timing
        while reaper.time_precise() < targetTime do
          -- Force CPU to actually wait
        end
      end
    end
  else
    -- Normal mode: play all notes at once
    for noteIndex = 1, #chordNotesArray do
      playMidiNote(chordNotesArray[noteIndex])
    end
  end

  setNotesThatArePlaying(chordNotesArray) 
end

-- Chord Progression Functions
function addChordToProgression(scaleNoteIndex, chordTypeIndex, chordText, targetSlotOverride)
  local targetSlot = targetSlotOverride
  
  -- If no specific slot is specified, find first empty slot
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
      beats = 1,  -- How many beats this chord plays (1, 2, 4, 8)
      repeats = 1  -- How many times this slot repeats (1-4)
    }
  end
end

function clearChordProgression()
  chordProgression = {}
  progressionPlaying = false
  currentProgressionIndex = 0
end

function removeChordFromProgression(index)
  -- Set slot to nil instead of removing, so other slots don't shift
  if index > 0 and index <= maxProgressionSlots then
    chordProgression[index] = nil
  end
end

function insertProgressionToMIDI()
  -- Insert entire chord progression as MIDI at play cursor position
  local take = activeTake()
  if not take then
    reaper.ShowMessageBox("No active MIDI take found. Please open a MIDI editor.", "Error", 0)
    return
  end
  
  -- Check for chords
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
  
  -- Get start position and calculate PPQ per beat
  local startPPQ = getCursorPositionPPQ()
  local startQN = reaper.MIDI_GetProjQNFromPPQPos(take, startPPQ)
  local testPPQ = reaper.MIDI_GetPPQPosFromProjQN(take, startQN + 1.0)
  local oneBeatInPPQ = testPPQ - startPPQ
  
  local currentPPQ = startPPQ
  local velocity = getCurrentVelocity()
  local channel = getCurrentNoteChannel()
  
  reaper.Undo_BeginBlock()
  reaper.MIDI_DisableSort(take)
  
  local totalNotesInserted = 0
  
  -- Loop through progression slots up to progressionLength
  for slotIndex = 1, progressionLength do
    local slot = chordProgression[slotIndex]
    
    if slot then
      -- Get chord data
      local root = scaleNotes[slot.scaleNoteIndex]
      local chordData = scaleChords[slot.scaleNoteIndex][slot.chordTypeIndex]
      local octave = getOctave()
      local notes = getChordNotesArray(root, chordData, octave)
      
      local beats = slot.beats or 1
      local repeats = slot.repeats or 1
      
      -- Insert this chord 'repeats' times
      for repeatIndex = 1, repeats do
        -- Calculate note duration in PPQ
        local noteDurationPPQ = oneBeatInPPQ * beats
        
        -- Insert all notes in the chord
        for noteIndex, note in ipairs(notes) do
          local noteStartPPQ = currentPPQ
          local noteEndPPQ = currentPPQ + noteDurationPPQ
          
          -- Apply strum offset if enabled
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
        
        -- Move forward by beat duration
        currentPPQ = currentPPQ + noteDurationPPQ
      end
    else
      -- Empty slot - insert silence (just advance time)
      currentPPQ = currentPPQ + oneBeatInPPQ
    end
  end
  
  reaper.MIDI_Sort(take)
  reaper.Undo_EndBlock("Insert Chord Progression", -1)
  
  -- Force MIDI editor and project update
  reaper.MarkProjectDirty(0)
  reaper.UpdateArrange()
  reaper.UpdateTimeline()
  
  local mediaItem = reaper.GetMediaItemTake_Item(take)
  if mediaItem then
    reaper.UpdateItemInProject(mediaItem)
  end
end

-- Progression Preset Functions
local presetFolder = reaper.GetResourcePath() .. "/Scripts/TK Scripts/pandabot_ChordGun(TK MOD)/Presets/"

function ensurePresetFolderExists()
  -- Create preset folder if it doesn't exist
  local result = reaper.RecursiveCreateDirectory(presetFolder, 0)
  return result ~= 0
end

function saveProgressionPreset()
  ensurePresetFolderExists()
  
  -- Check if progression has chords
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
  
  -- Ask for preset name
  local retval, presetName = reaper.GetUserInputs("Save Progression Preset", 1, "Preset Name:,extrawidth=100", "")
  if not retval or presetName == "" then return end
  
  -- Sanitize filename
  presetName = presetName:gsub("[^%w%s%-_]", "")
  
  local filePath = presetFolder .. presetName .. ".txt"
  local file = io.open(filePath, "w")
  
  if not file then
    reaper.ShowMessageBox("Could not create preset file!", "Error", 0)
    return
  end
  
  -- Write progression data
  -- Format per slot: scaleNoteIndex,chordTypeIndex,text,beats,repeats
  for i = 1, maxProgressionSlots do
    if chordProgression[i] then
      local slot = chordProgression[i]
      file:write(slot.scaleNoteIndex .. "," .. slot.chordTypeIndex .. "," .. slot.text .. "," .. slot.beats .. "," .. slot.repeats .. "\n")
    else
      file:write("\n")  -- Empty line for empty slot
    end
  end
  
  -- Write progression length on last line
  file:write("LENGTH:" .. progressionLength .. "\n")
  
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
  
  -- Clear current progression
  chordProgression = {}
  
  -- Read preset data
  local slotIndex = 1
  for line in file:lines() do
    if line:match("^LENGTH:") then
      -- Parse progression length
      local length = tonumber(line:match("LENGTH:(%d+)"))
      if length then
        progressionLength = length
      end
    elseif line ~= "" and slotIndex <= maxProgressionSlots then
      -- Parse slot data: scaleNoteIndex,chordTypeIndex,text,beats,repeats
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
      -- Empty line = empty slot
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
  
  -- Build menu with load and delete options
  local menuStr = ""
  
  -- Add load presets
  for i, preset in ipairs(presets) do
    menuStr = menuStr .. preset .. "|"
  end
  
  -- Add separator and delete options
  menuStr = menuStr .. ">Delete preset|"
  for i, preset in ipairs(presets) do
    menuStr = menuStr .. preset
    if i < #presets then
      menuStr = menuStr .. "|"
    end
  end
  
  local result = gfx.showmenu(menuStr)
  
  if result > 0 and result <= #presets then
    -- Load preset
    loadProgressionPreset(presets[result])
  elseif result > #presets then
    -- Delete preset (submenu items start after load items)
    local deleteIndex = result - #presets
    if deleteIndex > 0 and deleteIndex <= #presets then
      local presetName = presets[deleteIndex]
      
      -- Confirm deletion
      local confirm = reaper.ShowMessageBox("Delete preset '" .. presetName .. "'?", "Confirm Delete", 4)
      if confirm == 6 then  -- Yes
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
  -- No longer needed - integrated into showLoadPresetMenu
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
  
  -- Play notes directly without stopping (progression handles stop/start timing)
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
  
  -- Check if progression has any chords
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
  
  -- Get beats from current slot (or use default if slot is empty)
  local currentSlotBeats = 1
  if chordProgression[currentProgressionIndex] then
    currentSlotBeats = chordProgression[currentProgressionIndex].beats or 1
  end
  
  local beatDuration = (60.0 / bpm) * currentSlotBeats
  
  if currentTime - progressionLastBeatTime >= beatDuration then
    -- Check if we need to repeat current slot
    local currentSlotRepeats = 1
    if chordProgression[currentProgressionIndex] then
      currentSlotRepeats = chordProgression[currentProgressionIndex].repeats or 1
    end
    
    currentProgressionRepeat = currentProgressionRepeat + 1
    
    -- If we haven't finished all repeats, stay on this slot
    if currentProgressionRepeat < currentSlotRepeats then
      -- Update timing for next repeat
      progressionLastBeatTime = progressionLastBeatTime + beatDuration
      
      -- Replay same chord (stop and restart for clean sound)
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
        
        -- Play with strum if enabled
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
      return  -- Don't advance to next slot yet
    end
    
    -- All repeats done, move to next slot
    currentProgressionRepeat = 0
    currentProgressionIndex = currentProgressionIndex + 1
    if currentProgressionIndex > progressionLength then
      currentProgressionIndex = 1  -- Loop back to slot 1
    end
    
    -- Update timing BEFORE playing to keep strict tempo
    progressionLastBeatTime = progressionLastBeatTime + beatDuration
    
    -- Stop old notes
    local oldNotes = getNotesThatArePlaying()
    for i = 1, #oldNotes do
      stopNoteFromPlaying(oldNotes[i])
    end
    
    -- Get new chord notes from current slot
    local chord = chordProgression[currentProgressionIndex]
    if chord then
      -- Slot has a chord - play it
      setSelectedScaleNote(chord.scaleNoteIndex)
      setSelectedChordType(chord.scaleNoteIndex, chord.chordTypeIndex)
      
      local root = scaleNotes[chord.scaleNoteIndex]
      local chordData = scaleChords[chord.scaleNoteIndex][chord.chordTypeIndex]
      local octave = getOctave()
      local newNotes = getChordNotesArray(root, chordData, octave)
      
      -- Play new notes (met strum als enabled)
      if strumEnabled then
        -- Strum mode: play notes with delay
        local delaySeconds = strumDelayMs / 1000.0
        
        for noteIndex = 1, #newNotes do
          playMidiNote(newNotes[noteIndex])
          
          -- Wait before playing next note (except after last note)
          if noteIndex < #newNotes then
            local startTime = reaper.time_precise()
            local targetTime = startTime + delaySeconds
            
            -- Busy wait for precise timing
            while reaper.time_precise() < targetTime do
              -- Force CPU to actually wait
            end
          end
        end
      else
        -- Normal mode: play all notes at once
        for i = 1, #newNotes do
          playMidiNote(newNotes[i])
        end
      end
      
      setNotesThatArePlaying(newNotes)
      updateChordText(root, chordData, newNotes)
    else
      -- Slot is empty - silence (notes already stopped)
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

function playOrInsertScaleChord(actionDescription)

  local scaleNoteIndex = getSelectedScaleNote()
  local chordTypeIndex = getSelectedChordType(scaleNoteIndex)

  local root = scaleNotes[scaleNoteIndex]
  local chord = scaleChords[scaleNoteIndex][chordTypeIndex]
  local octave = getOctave()
  
  local chordNotesArray = getChordNotesArray(root, chord, octave)

  if activeTake() ~= nil and notCurrentlyRecording() then

    startUndoBlock()

      if thereAreNotesSelected() then 
        changeSelectedNotesToScaleChords(chordNotesArray)
      else
        insertScaleChord(chordNotesArray, false)
      end

    endUndoBlock(actionDescription)
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

  if activeTake() ~= nil and notCurrentlyRecording() then

  	startUndoBlock()

		  if thereAreNotesSelected() then 
		    changeSelectedNotesToScaleNotes(noteValue)
		  else
		    insertScaleNote(noteValue, false)
		  end

		endUndoBlock(actionDescription)
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
	setColor("FFD700")  -- Goud/geel voor ingedrukte button
end

function setDrawColorToPressedButtonText()
	setColor("1A1A1A")  -- Donkere tekst voor contrast op geel
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
	setColor("2E5C8A")  -- Donkerblauw voor outline
end

function setDrawColorToHeaderBackground()
	setColor("4A90D9")  -- Lichtblauw voor achtergrond
end

function setDrawColorToHeaderText()
	setColor("E8F4FF")  -- Bijna wit/lichtblauw voor tekst
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
	local backgroundColor = {36, 36, 36, 1}		-- #242424
	gfx.set(table.unpack(backgroundColor))
end

function setDrawColorToNormalButton()

	local backgroundColor = {45, 45, 45, 1}		-- #2D2D2D
	gfx.set(table.unpack(backgroundColor))
end

function setDrawColorToHighlightedButton()

	local backgroundColor = {71, 71, 71, 1}		-- #474747
	gfx.set(table.unpack(backgroundColor))
end

function setDrawColorToSelectedButton()

	local backgroundColor = {220, 220, 220, 1}	-- #DCDCDC
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

  if rightMouseButtonIsHeldDown() and windowIsDocked() then
    self:drawUndockWindowContextMenu()
  end

  if rightMouseButtonIsHeldDown() and windowIsNotDocked() then
    self:drawDockWindowContextMenu()
  end
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

function Label:new(x, y, width, height, getTextCallback)

  local self = {}
  setmetatable(self, Label)

  self.x = x
  self.y = y
  self.width = width
  self.height = height
  self.getTextCallback = getTextCallback

  return self
end

function Label:drawRedOutline()
  setDrawColorToRed()
  gfx.rect(self.x, self.y, self.width, self.height, false)
end

function Label:drawText(text)

	setDrawColorToText()
	local stringWidth, stringHeight = gfx.measurestr(text)
	gfx.x = self.x + ((self.width - stringWidth) / 2)
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

-- Maak radius een functie zodat het dynamisch schaalt
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

-- Maak radius een functie zodat het dynamisch schaalt
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

-- Track which button is currently being held
local currentlyHeldButton = nil
-- Hold mode - when true, notes continue playing after mouse release
local holdModeEnabled = false
-- Track the last played chord info (for piano keyboard display in hold mode)
local lastPlayedChord = nil

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

		-- Check if this button is currently being pressed
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

	-- Check if this button is currently being pressed
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
	-- Add chord to progression
	-- Use selected slot if available, otherwise find first empty slot
	local chord = scaleChords[self.scaleNoteIndex][self.chordTypeIndex]
	addChordToProgression(self.scaleNoteIndex, self.chordTypeIndex, self.text, selectedProgressionSlot)
	
	-- Play the chord ook zodat je het hoort (net als bij normale click)
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
	
	-- Handle mouse button press (start playing)
	if mouseButtonIsNotPressedDown and isHovering and leftButtonDown then
		mouseButtonIsNotPressedDown = false
		currentlyHeldButton = self
		lastPlayedChord = self  -- Remember this chord for piano display
		
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
	
	-- Handle mouse button release (stop playing)
	if currentlyHeldButton == self and not leftButtonDown then
		-- Only stop if hold mode is disabled
		if not holdModeEnabled then
			stopAllNotesFromPlaying()
			lastPlayedChord = nil  -- Clear piano display when stopping
		end
		-- In hold mode, keep lastPlayedChord so piano stays visible
		currentlyHeldButton = nil
	end
	
	-- Right click to stop all notes
	if mouseButtonIsNotPressedDown and buttonHasBeenRightClicked(self) then
		mouseButtonIsNotPressedDown = false
		stopAllNotesFromPlaying()
		currentlyHeldButton = nil
		lastPlayedChord = nil  -- Clear piano display
	end
end

-- Simple button for HOLD and KILL
SimpleButton = {}
SimpleButton.__index = SimpleButton

function SimpleButton:new(text, x, y, width, height, onClick, onRightClick)
	local self = {}
	setmetatable(self, SimpleButton)
	self.text = text
	self.x = x
	self.y = y
	self.width = width
	self.height = height
	self.onClick = onClick
	self.onRightClick = onRightClick  -- Optional right-click handler
	return self
end

function SimpleButton:draw()
	-- No background or outline - just text
	
	-- Draw text - highlight when hovering
	if mouseIsHoveringOver(self) then
		setColor("FFD700")  -- Geel bij hover
	else
		setColor("CCCCCC")  -- Normaal grijs
	end
	
	local stringWidth, stringHeight = gfx.measurestr(self.text)
	gfx.x = self.x + ((self.width - stringWidth) / 2)
	gfx.y = self.y + ((self.height - stringHeight) / 2)
	gfx.drawstr(self.text)
end

function SimpleButton:update()
	self:draw()
	
	if mouseButtonIsNotPressedDown and mouseIsHoveringOver(self) then
		-- Check for right-click first (before dock menu can intercept)
		if self.onRightClick and gfx.mouse_cap == 2 then
			mouseButtonIsNotPressedDown = false
			self.onRightClick()
		elseif leftMouseButtonIsHeldDown() then
			mouseButtonIsNotPressedDown = false
			self.onClick()
		end
	end
end

-- Toggle button for HOLD mode
ToggleButton = {}
ToggleButton.__index = ToggleButton

function ToggleButton:new(text, x, y, width, height, getState, onToggle, onRightClick)
	local self = {}
	setmetatable(self, ToggleButton)
	self.text = text
	self.x = x
	self.y = y
	self.width = width
	self.height = height
	self.getState = getState
	self.onToggle = onToggle
	self.onRightClick = onRightClick  -- Optional right-click handler
	return self
end

function ToggleButton:draw()
	-- No background or outline - just text
	local isActive = self.getState()
	
	-- Draw text - color changes based on state
	if isActive then
		setColor("FFD700")  -- Geel wanneer actief
	elseif mouseIsHoveringOver(self) then
		setColor("FFFFFF")  -- Wit bij hover
	else
		setColor("CCCCCC")  -- Normaal grijs
	end
	
	local stringWidth, stringHeight = gfx.measurestr(self.text)
	gfx.x = self.x + ((self.width - stringWidth) / 2)
	gfx.y = self.y + ((self.height - stringHeight) / 2)
	gfx.drawstr(self.text)
end

function ToggleButton:update()
	self:draw()
	
	if mouseButtonIsNotPressedDown and mouseIsHoveringOver(self) and leftMouseButtonIsHeldDown() then
		mouseButtonIsNotPressedDown = false
		
		-- Check for Ctrl+Click first (for settings)
		if self.onRightClick and ctrlModifierIsHeldDown() then
			self.onRightClick()
		else
			-- Normal click to toggle
			self.onToggle()
		end
	end
end

-- Cycle Button (cycles through multiple options)
CycleButton = {}
CycleButton.__index = CycleButton

function CycleButton:new(x, y, width, height, options, getCurrentIndex, onCycle)
	local self = {}
	setmetatable(self, CycleButton)
	self.x = x
	self.y = y
	self.width = width
	self.height = height
	self.options = options  -- Array of strings like {"1.0x", "1.5x", "2.0x"}
	self.getCurrentIndex = getCurrentIndex  -- Function that returns current index (1-based)
	self.onCycle = onCycle  -- Function called when cycling, receives new index
	return self
end

function CycleButton:draw()
	-- No background or outline - just text
	local currentIndex = self.getCurrentIndex()
	local text = self.options[currentIndex] or "?"
	
	-- Draw text
	if mouseIsHoveringOver(self) then
		setColor("FFD700")  -- Geel bij hover
	else
		setColor("CCCCCC")  -- Normaal grijs
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

-- Help Window Function
function showHelpWindow()
	-- Get the directory of the current script
	local scriptPath = debug.getinfo(1, "S").source:match("@?(.*)")
	local scriptDir = scriptPath:match("(.+)[/\\]")
	local helpScriptPath = scriptDir .. "/TK_ChordGun_Help.lua"
	
	-- Run the help script in a separate gfx context
	reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS7d3c_3032f3b65cf64a5a833f9daf9793b663"), 0) -- Script: Run script...
	
	-- Alternative: directly run the script
	local command = reaper.AddRemoveReaScript(true, 0, helpScriptPath, true)
	if command > 0 then
		reaper.Main_OnCommand(command, 0)
		reaper.AddRemoveReaScript(false, 0, helpScriptPath, true)
	end
end

-- Piano Keyboard Visualizer
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

-- ProgressionSlots class
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
	local slotWidth = (self.width - s(14)) / 8  -- Verdeel breedte over 8 slots
	local slotHeight = self.height
	
	-- Teken elk slot
	for i = 1, maxProgressionSlots do
		local x = self.x + ((i - 1) * slotWidth) + ((i - 1) * s(2))
		local y = self.y
		
		-- Check if mouse is hovering over this slot
		local isHovering = gfx.mouse_x >= x and gfx.mouse_x <= x + slotWidth and
		                   gfx.mouse_y >= y and gfx.mouse_y <= y + slotHeight
		
		-- Background color
		local bgColor = {0.15, 0.15, 0.15}
		if currentProgressionIndex == i and progressionPlaying then
			bgColor = {0.2, 0.4, 0.6}  -- Blue highlight voor current playing slot
		elseif selectedProgressionSlot == i then
			bgColor = {0.3, 0.5, 0.3}  -- Green highlight voor selected slot
		elseif isHovering then
			bgColor = {0.2, 0.2, 0.2}  -- Lichter grijs bij hover
		end
		
		-- Teken rounded rectangle (simpel, zonder radius voor nu)
		gfx.set(bgColor[1], bgColor[2], bgColor[3], 1)
		gfx.rect(x, y, slotWidth, slotHeight, true)
		
		-- Border (dikker voor selected slot)
		if selectedProgressionSlot == i then
			gfx.set(0.5, 0.7, 0.5, 1)  -- Groene border voor selected
			gfx.rect(x, y, slotWidth, slotHeight, false)
			gfx.rect(x+1, y+1, slotWidth-2, slotHeight-2, false)  -- Dubbele border
		else
			gfx.set(0.3, 0.3, 0.3, 1)
			gfx.rect(x, y, slotWidth, slotHeight, false)
		end
		
		-- Loop endpoint indicator (orange right border)
		if i == progressionLength then
			gfx.set(1, 0.6, 0, 1)  -- Oranje kleur
			gfx.rect(x + slotWidth - s(3), y, s(3), slotHeight, true)
		end
		
		-- Tekst (chord naam)
		if chordProgression[i] then
			-- Chord naam (bovenaan)
			gfx.set(1, 1, 1, 1)
			gfx.setfont(1, "Arial", s(13))
			local textW, textH = gfx.measurestr(chordProgression[i].text)
			gfx.x = x + (slotWidth - textW) / 2
			gfx.y = y + s(5)
			gfx.drawstr(chordProgression[i].text)
			
			-- Beats en Repeats info (onderaan, klein)
			local beats = chordProgression[i].beats or 1
			local repeats = chordProgression[i].repeats or 1
			local infoText = beats .. "b"
			if repeats > 1 then
				infoText = infoText .. " x" .. repeats
			end
			gfx.set(0.7, 0.7, 0.7, 1)
			gfx.setfont(1, "Arial", s(10))
			local infoW, infoH = gfx.measurestr(infoText)
			gfx.x = x + (slotWidth - infoW) / 2
			gfx.y = y + slotHeight - infoH - s(3)
			gfx.drawstr(infoText)
		else
			-- Lege slot - toon nummer
			gfx.set(0.4, 0.4, 0.4, 1)
			gfx.setfont(1, "Arial", s(12))
			local num = tostring(i)
			local textW, textH = gfx.measurestr(num)
			gfx.x = x + (slotWidth - textW) / 2
			gfx.y = y + (slotHeight - textH) / 2
			gfx.drawstr(num)
		end
		
		-- Check for Shift+Left-click to set loop length (VOOR normal click, anders wordt slot geselecteerd)
		if mouseButtonIsNotPressedDown and isHovering and gfx.mouse_cap & 1 == 1 and shiftModifierIsHeldDown() then
			progressionLength = i  -- Set loop endpoint to clicked slot
			mouseButtonIsNotPressedDown = false
		-- Check for Ctrl+Left-click to set beats and repeats
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
				
				-- Validate beats (must be 1, 2, 4, or 8)
				if beats and (beats == 1 or beats == 2 or beats == 4 or beats == 8) then
					chordProgression[i].beats = beats
				end
				
				-- Validate repeats (1-4)
				if repeats and repeats >= 1 and repeats <= 4 then
					chordProgression[i].repeats = math.floor(repeats)
				end
			end
			mouseButtonIsNotPressedDown = false
		-- Check for left-click to select/deselect slot (alleen als GEEN shift/ctrl)
		elseif mouseButtonIsNotPressedDown and isHovering and gfx.mouse_cap & 1 == 1 and not altModifierIsHeldDown() and not shiftModifierIsHeldDown() and not ctrlModifierIsHeldDown() then
			if selectedProgressionSlot == i then
				-- Click op dezelfde slot = deselect
				selectedProgressionSlot = nil
			else
				-- Click op andere slot = select
				selectedProgressionSlot = i
			end
			mouseButtonIsNotPressedDown = false
		end
		
		-- Check for Alt+Right-click to clear slot
		if mouseButtonIsNotPressedDown and chordProgression[i] and isHovering then
			if altModifierIsHeldDown() and gfx.mouse_cap & 2 == 2 then  -- Alt+Right click
				removeChordFromProgression(i)
				mouseButtonIsNotPressedDown = false
			end
		end
	end
end

function PianoKeyboard:getStartNote()
	-- Bereken dynamisch de start note op basis van huidig octaaf
	local currentOctave = getOctave()
	return (currentOctave * 12) + 12  -- C van het huidige octaaf
end

function PianoKeyboard:getNoteFromPosition(noteNumber)
	-- Convert MIDI note to position on keyboard
	local startNote = self:getStartNote()
	local relativeNote = noteNumber - startNote
	if relativeNote < 0 or relativeNote >= (self.numOctaves * 12) then
		return nil
	end
	
	local octave = math.floor(relativeNote / 12)
	local noteInOctave = relativeNote % 12
	
	-- Map to white key position
	local whiteKeyMap = {0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6}  -- C, C#, D, D#, E, F, F#, G, G#, A, A#, B
	local isBlack = {false, true, false, true, false, false, true, false, true, false, true, false}
	
	local whiteKeyIndex = whiteKeyMap[noteInOctave + 1] + (octave * 7)
	
	return {
		whiteKeyIndex = whiteKeyIndex,
		isBlack = isBlack[noteInOctave + 1],
		noteInOctave = noteInOctave
	}
end

function PianoKeyboard:getActiveNotes()
	-- Get currently playing notes from the chord
	local activeNotes = {}
	
	-- Check if there's a currently held button OR a last played chord in hold mode
	local activeButton = currentlyHeldButton or lastPlayedChord
	
	if activeButton then
		local selectedScaleNote = getSelectedScaleNote()
		local selectedChordType = getSelectedChordType(selectedScaleNote)
		
		if selectedScaleNote and selectedChordType then
			local root = scaleNotes[selectedScaleNote]
			local chord = scaleChords[selectedScaleNote][selectedChordType]
			local octave = getOctave()
			
			-- Use the same logic as getChordNotesArray
			local chordPattern = chord["pattern"]
			for n = 0, #chordPattern-1 do
				if chordPattern:sub(n+1, n+1) == '1' then
					local noteValue = root + n + ((octave+1) * 12) - 1
					table.insert(activeNotes, noteValue)
				end
			end
			
			-- Apply inversion
			activeNotes = applyInversion(activeNotes)
		end
	end
	
	return activeNotes
end

function PianoKeyboard:drawWhiteKey(index, isActive, noteNumber)
	local x = self.x + (index * self.whiteKeyWidth)
	local y = self.y
	local w = self.whiteKeyWidth - s(1)  -- Small gap between keys
	local h = self.height
	
	-- Check if note is in scale
	-- noteNumber is MIDI note (60 = middle C, etc.)
	-- We need to convert to 1-based index for noteIsInScale
	-- MIDI: C=0,C#=1,D=2... modulo 12
	-- Lua index: C=1,C#=2,D=3... (1-12)
	local noteInChromatic = noteNumber % 12  -- 0-11 (C=0, C#=1, etc.)
	local noteForScale = noteInChromatic + 1  -- Convert to 1-12 to match getNotesIndex output
	local inScale = scalePattern[noteForScale] or false
	
	-- Draw key
	if isActive then
		setColor("FFD700")  -- Gold when active
	elseif inScale then
		setColor("F0F0F0")  -- Off-white voor noten in de scale
	else
		setColor("C0C0C0")  -- Grijs voor noten buiten de scale
	end
	gfx.rect(x, y, w, h, true)
	
	-- Draw outline
	setColor("000000")
	gfx.rect(x, y, w, h, false)
	
	-- Draw note name
	local noteName = notes[noteForScale]
	gfx.setfont(1, "Arial", s(14))
	local stringWidth, stringHeight = gfx.measurestr(noteName)
	
	-- Use dark text for light keys, light text for active keys
	if isActive then
		setColor("000000")  -- Zwart op goud
	else
		setColor("333333")  -- Donkergrijs op wit/grijs
	end
	
	gfx.x = x + (w - stringWidth) / 2
	gfx.y = y + h - stringHeight - s(4)  -- Onderaan de toets
	gfx.drawstr(noteName)
	
	-- Reset font
	gfx.setfont(1, "Arial", s(15))
end

function PianoKeyboard:drawBlackKey(whiteKeyIndex, noteInOctave, isActive, noteNumber)
	local x = self.x + ((whiteKeyIndex + 1) * self.whiteKeyWidth) - (self.blackKeyWidth / 2)
	local y = self.y
	local w = self.blackKeyWidth
	local h = self.blackKeyHeight
	
	-- Check if note is in scale
	-- noteNumber is MIDI note, convert to 1-based index for scalePattern
	local noteInChromatic = noteNumber % 12  -- 0-11 (C=0, C#=1, etc.)
	local noteForScale = noteInChromatic + 1  -- Convert to 1-12
	local inScale = scalePattern[noteForScale] or false
	
	-- Draw key
	if isActive then
		setColor("FFD700")  -- Gold when active
	elseif inScale then
		setColor("1A1A1A")  -- Dark gray/black voor zwarte toetsen in scale
	else
		setColor("606060")  -- Donkerder grijs voor zwarte toetsen buiten scale
	end
	gfx.rect(x, y, w, h, true)
	
	-- Draw outline
	setColor("000000")
	gfx.rect(x, y, w, h, false)
	
	-- Draw note name
	local noteName = notes[noteForScale]
	gfx.setfont(1, "Arial", s(12))
	local stringWidth, stringHeight = gfx.measurestr(noteName)
	
	-- Use light text for dark keys
	if isActive then
		setColor("000000")  -- Zwart op goud
	else
		setColor("FFFFFF")  -- Wit op zwart/grijs
	end
	
	gfx.x = x + (w - stringWidth) / 2
	gfx.y = y + h - stringHeight - s(3)  -- Onderaan de toets
	gfx.drawstr(noteName)
	
	-- Reset font
	gfx.setfont(1, "Arial", s(15))
end

function PianoKeyboard:draw()
	-- Get active notes
	local activeNotes = self:getActiveNotes()
	local activeNoteSet = {}
	for _, note in ipairs(activeNotes) do
		activeNoteSet[note] = true
	end
	
	local startNote = self:getStartNote()  -- Gebruik dynamische startNote
	
	-- Draw white keys first
	for i = 0, self.numWhiteKeys - 1 do
		local octave = math.floor(i / 7)
		local keyInOctave = i % 7
		local noteNumber = startNote + (octave * 12)
		
		-- Map white key to MIDI note
		local whiteKeyToNote = {0, 2, 4, 5, 7, 9, 11}  -- C, D, E, F, G, A, B
		noteNumber = noteNumber + whiteKeyToNote[keyInOctave + 1]
		
		local isActive = activeNoteSet[noteNumber] or false
		self:drawWhiteKey(i, isActive, noteNumber)  -- Geef noteNumber door
	end
	
	-- Draw black keys on top
	for i = 0, self.numWhiteKeys - 1 do
		local octave = math.floor(i / 7)
		local keyInOctave = i % 7
		
		if self.blackKeyPattern[keyInOctave + 1] == 1 then
			local startNote = self:getStartNote()  -- Gebruik dynamische startNote
			local noteNumber = startNote + (octave * 12)
			local whiteKeyToNote = {0, 2, 4, 5, 7, 9, 11}
			noteNumber = noteNumber + whiteKeyToNote[keyInOctave + 1] + 1  -- +1 for sharp
			
			local isActive = activeNoteSet[noteNumber] or false
			self:drawBlackKey(i, keyInOctave, isActive, noteNumber)  -- Geef noteNumber door
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
	local commandId = 40047
	reaper.MIDIEditor_OnCommand(activeMidiEditor(), commandId)
end

local function moveEditCursorRightByGrid()
	local commandId = 40048
	reaper.MIDIEditor_OnCommand(activeMidiEditor(), commandId)
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

	if inputCharacter == inputCharacters["1"] then
		previewScaleChordAction(1)
	end

	if inputCharacter == inputCharacters["2"] then
		previewScaleChordAction(2)
	end

	if inputCharacter == inputCharacters["3"] then
		previewScaleChordAction(3)
	end

	if inputCharacter == inputCharacters["4"] then
		previewScaleChordAction(4)
	end

	if inputCharacter == inputCharacters["5"] then
		previewScaleChordAction(5)
	end

	if inputCharacter == inputCharacters["6"] then
		previewScaleChordAction(6)
	end

	if inputCharacter == inputCharacters["7"] then
		previewScaleChordAction(7)
	end

	--


	if inputCharacter == inputCharacters["!"] then
		scaleChordAction(1)
	end

	if inputCharacter == inputCharacters["@"] then
		scaleChordAction(2)
	end

	if inputCharacter == inputCharacters["#"] then
		scaleChordAction(3)
	end

	if inputCharacter == inputCharacters["$"] then
		scaleChordAction(4)
	end

	if inputCharacter == inputCharacters["%"] then
		scaleChordAction(5)
	end

	if inputCharacter == inputCharacters["^"] then
		scaleChordAction(6)
	end

	if inputCharacter == inputCharacters["&"] then
		scaleChordAction(7)
	end

	--


	if inputCharacter == inputCharacters["q"] then
		previewHigherScaleNoteAction(1)
	end

	if inputCharacter == inputCharacters["w"] then
		previewHigherScaleNoteAction(2)
	end

	if inputCharacter == inputCharacters["e"] then
		previewHigherScaleNoteAction(3)
	end

	if inputCharacter == inputCharacters["r"] then
		previewHigherScaleNoteAction(4)
	end

	if inputCharacter == inputCharacters["t"] then
		previewHigherScaleNoteAction(5)
	end

	if inputCharacter == inputCharacters["y"] then
		previewHigherScaleNoteAction(6)
	end

	if inputCharacter == inputCharacters["u"] then
		previewHigherScaleNoteAction(7)
	end

	--

	if inputCharacter == inputCharacters["a"] then
		previewScaleNoteAction(1)
	end

	if inputCharacter == inputCharacters["s"] then
		previewScaleNoteAction(2)
	end

	if inputCharacter == inputCharacters["d"] then
		previewScaleNoteAction(3)
	end

	if inputCharacter == inputCharacters["f"] then
		previewScaleNoteAction(4)
	end

	if inputCharacter == inputCharacters["g"] then
		previewScaleNoteAction(5)
	end

	if inputCharacter == inputCharacters["h"] then
		previewScaleNoteAction(6)
	end

	if inputCharacter == inputCharacters["j"] then
		previewScaleNoteAction(7)
	end

	--

	if inputCharacter == inputCharacters["z"] then
		previewLowerScaleNoteAction(1)
	end

	if inputCharacter == inputCharacters["x"] then
		previewLowerScaleNoteAction(2)
	end

	if inputCharacter == inputCharacters["c"] then
		previewLowerScaleNoteAction(3)
	end

	if inputCharacter == inputCharacters["v"] then
		previewLowerScaleNoteAction(4)
	end

	if inputCharacter == inputCharacters["b"] then
		previewLowerScaleNoteAction(5)
	end

	if inputCharacter == inputCharacters["n"] then
		previewLowerScaleNoteAction(6)
	end

	if inputCharacter == inputCharacters["m"] then
		previewLowerScaleNoteAction(7)
	end



	--


	if inputCharacter == inputCharacters["Q"] then
		higherScaleNoteAction(1)
	end

	if inputCharacter == inputCharacters["W"] then
		higherScaleNoteAction(2)
	end

	if inputCharacter == inputCharacters["E"] then
		higherScaleNoteAction(3)
	end

	if inputCharacter == inputCharacters["R"] then
		higherScaleNoteAction(4)
	end

	if inputCharacter == inputCharacters["T"] then
		higherScaleNoteAction(5)
	end

	if inputCharacter == inputCharacters["Y"] then
		higherScaleNoteAction(6)
	end

	if inputCharacter == inputCharacters["U"] then
		higherScaleNoteAction(7)
	end

	--

	if inputCharacter == inputCharacters["A"] then
		scaleNoteAction(1)
	end

	if inputCharacter == inputCharacters["S"] then
		scaleNoteAction(2)
	end

	if inputCharacter == inputCharacters["D"] then
		scaleNoteAction(3)
	end

	if inputCharacter == inputCharacters["F"] then
		scaleNoteAction(4)
	end

	if inputCharacter == inputCharacters["G"] then
		scaleNoteAction(5)
	end

	if inputCharacter == inputCharacters["H"] then
		scaleNoteAction(6)
	end

	if inputCharacter == inputCharacters["J"] then
		scaleNoteAction(7)
	end

	--

	if inputCharacter == inputCharacters["Z"] then
		lowerScaleNoteAction(1)
	end

	if inputCharacter == inputCharacters["X"] then
		lowerScaleNoteAction(2)
	end

	if inputCharacter == inputCharacters["C"] then
		lowerScaleNoteAction(3)
	end

	if inputCharacter == inputCharacters["V"] then
		lowerScaleNoteAction(4)
	end

	if inputCharacter == inputCharacters["B"] then
		lowerScaleNoteAction(5)
	end

	if inputCharacter == inputCharacters["N"] then
		lowerScaleNoteAction(6)
	end

	if inputCharacter == inputCharacters["M"] then
		lowerScaleNoteAction(7)
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
  self.width = interfaceWidth
  self.height = interfaceHeight
  self.lastWidth = interfaceWidth
  self.lastHeight = interfaceHeight

  self.elements = {}

  return self
end

function Interface:restartGui()
	self.elements = {}
	self.width = interfaceWidth
	self.height = interfaceHeight
	self.lastWidth = interfaceWidth
	self.lastHeight = interfaceHeight
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
	
	-- Set scaled font size
	gfx.setfont(1, "Arial", s(15))
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

function Interface:addLabel(x, y, width, height, getTextCallback)

	local label = Label:new(x, y, width, height, getTextCallback)
	table.insert(self.elements, label)
end

function Interface:addDropdown(x, y, width, height, options, defaultOptionIndex, onSelectionCallback)

	local dropdown = Dropdown:new(x, y, width, height, options, defaultOptionIndex, onSelectionCallback)
	table.insert(self.elements, dropdown)
end

function Interface:addSimpleButton(text, x, y, width, height, onClick, onRightClick)

	local button = SimpleButton:new(text, x, y, width, height, onClick, onRightClick)
	table.insert(self.elements, button)
end

function Interface:addToggleButton(text, x, y, width, height, getState, onToggle, onRightClick)

	local button = ToggleButton:new(text, x, y, width, height, getState, onToggle, onRightClick)
	table.insert(self.elements, button)
end

function Interface:addCycleButton(x, y, width, height, options, getCurrentIndex, onCycle)

	local button = CycleButton:new(x, y, width, height, options, getCurrentIndex, onCycle)
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
		element:update()
	end
end

function Interface:update()

	self:updateElements()
	gfx.update()
	
	-- Update chord progression playback
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

  -- Save dock state whenever it changes (docked or undocked)
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

-- Deze variabelen worden lokaal gedefinieerd in addTopFrame om scaling issues te voorkomen
-- local xMargin = s(8)
-- local yMargin = s(8)
-- local xPadding = s(16)
-- local yPadding = s(5)
-- local scaleLabelWidth = nil
-- local horizontalMargin = s(8)
-- local scaleTonicNoteWidth = s(50)
-- local scaleTypeWidth = s(150)
-- local octaveLabelWidth = nil
-- local octaveValueBoxWidth = s(55)

local scaleLabelWidth = nil
local octaveLabelWidth = nil

function Interface:addTopFrame()

	local keySelectionFrameHeight = s(25)
	self.keySelectionFrameHeight = keySelectionFrameHeight  -- Opslaan voor addBottomFrame
	local xMargin = s(8)
	local yMargin = s(8)
	local xPadding = s(16)
	local yPadding = s(5)
	local horizontalMargin = s(8)
	local scaleTonicNoteWidth = s(50)
	local scaleTypeWidth = s(150)
	local octaveValueBoxWidth = s(55)

	self:addFrame(xMargin+dockerXPadding, yMargin, self.width - 2 * xMargin, keySelectionFrameHeight)
	self:addScaleLabel(xMargin, yMargin, xPadding, yPadding)
	self:addScaleTonicNoteDropdown(xMargin, yMargin, xPadding, yPadding, horizontalMargin, scaleTonicNoteWidth)
	self:addScaleTypeDropdown(xMargin, yMargin, xPadding, yPadding, horizontalMargin, scaleTonicNoteWidth, scaleTypeWidth)
	self:addScaleNotesTextLabel(xMargin, yMargin, xPadding, yPadding, horizontalMargin, scaleTonicNoteWidth, scaleTypeWidth)
	self:addOctaveLabel(yMargin, yPadding)
	self:addOctaveSelectorValueBox(yMargin, xMargin, xPadding, octaveValueBoxWidth)
end

function Interface:addHoldButton(xMargin, yMargin, xPadding)

	local buttonWidth = s(60)
	local buttonHeight = s(18)
	local buttonXpos = xMargin + xPadding
	local buttonYpos = yMargin + s(6)  -- Bovenaan de bottom frame
	
	local getHoldState = function() return holdModeEnabled end
	local onToggle = function()
		holdModeEnabled = not holdModeEnabled
	end
	
	self:addToggleButton("HOLD", buttonXpos+dockerXPadding, buttonYpos, buttonWidth, buttonHeight, getHoldState, onToggle)
end

function Interface:addKillButton(xMargin, yMargin, xPadding)

	local buttonWidth = s(60)
	local buttonHeight = s(18)
	local buttonXpos = xMargin + xPadding + s(60) + s(8)  -- HOLD width + spacing
	local buttonYpos = yMargin + s(6)  -- Bovenaan de bottom frame
	
	local onClick = function()
		stopAllNotesFromPlaying()
		currentlyHeldButton = nil
		lastPlayedChord = nil  -- Clear piano display
	end
	
	self:addSimpleButton("KILL", buttonXpos+dockerXPadding, buttonYpos, buttonWidth, buttonHeight, onClick)
end

function Interface:addStrumButton(xMargin, yMargin, xPadding)

	local buttonWidth = s(60)
	local buttonHeight = s(18)
	local buttonXpos = xMargin + xPadding + s(60) + s(8) + s(60) + s(8)  -- Na HOLD en KILL
	local buttonYpos = yMargin + s(6)  -- Bovenaan de bottom frame
	
	local getStrumState = function() 
		return strumEnabled 
	end
	local onToggle = function()
		strumEnabled = not strumEnabled
	end
	local onCtrlClick = function()
		-- Open popup om strum delay in te stellen (Ctrl+Click)
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
	
	self:addToggleButton("STRUM", buttonXpos+dockerXPadding, buttonYpos, buttonWidth, buttonHeight, getStrumState, onToggle, onCtrlClick)
end



function Interface:addPianoKeyboard(xMargin, yMargin, xPadding, yPadding, headerHeight)

	local pianoWidth = self.width - 2 * xMargin - 2 * xPadding
	local pianoHeight = s(70)
	local pianoXpos = xMargin + xPadding
	
	-- Bereken positie onder alle chord buttons
	-- Gebruik dezelfde logica als chord button positioning: yMargin + yPadding + headerHeight + offset voor laatste button
	local buttonHeight = s(38)
	local innerSpacing = s(2)
	local numChordButtons = 13
	local pianoYpos = yMargin + yPadding + headerHeight + (numChordButtons * buttonHeight) + (numChordButtons * innerSpacing) - s(3) + s(6)
	
	-- Gebruik huidige octaaf in plaats van hardcoded octaaf 2
	-- getOctave() geeft het octaaf nummer (0-8)
	-- MIDI note = (octaaf * 12) + 12 voor C in dat octaaf
	local currentOctave = getOctave()
	local startNote = (currentOctave * 12) + 12  -- C van het huidige octaaf
	
	self:addPiano(pianoXpos+dockerXPadding, pianoYpos, pianoWidth, pianoHeight, startNote, 2)  -- 2 octaves vanaf huidig octaaf
end

function Interface:addProgressionSlots(xMargin, yMargin, xPadding, yPadding, headerHeight)
	-- Voeg de progression slots toe als UI element
	local slotWidth = self.width - 2 * xMargin - 2 * xPadding
	local slotHeight = s(30)
	local slotXpos = xMargin + xPadding
	
	-- Positioneer onder piano keyboard
	local buttonHeight = s(38)
	local innerSpacing = s(2)
	local numChordButtons = 13
	local pianoHeight = s(70)
	local pianoYpos = yMargin + yPadding + headerHeight + (numChordButtons * buttonHeight) + (numChordButtons * innerSpacing) - s(3) + s(6)
	local slotYpos = pianoYpos + pianoHeight + s(8)
	
	local slots = ProgressionSlots:new(slotXpos + dockerXPadding, slotYpos, slotWidth, slotHeight)
	table.insert(self.elements, slots)
end

function Interface:addProgressionControls(xMargin, yMargin, xPadding, yPadding, headerHeight)
	-- Voeg PLAY, STOP, CLEAR buttons toe onder de progression slots
	local buttonWidth = s(50)
	local buttonHeight = s(18)
	local buttonXpos = xMargin + xPadding
	
	-- Positioneer onder progression slots
	local buttonHeightChord = s(38)
	local innerSpacing = s(2)
	local numChordButtons = 13
	local pianoHeight = s(70)
	local slotHeight = s(30)
	local pianoYpos = yMargin + yPadding + headerHeight + (numChordButtons * buttonHeightChord) + (numChordButtons * innerSpacing) - s(3) + s(6)
	local slotYpos = pianoYpos + pianoHeight + s(8)
	local buttonYpos = slotYpos + slotHeight + s(6)
	
	-- PLAY button (links)
	self:addSimpleButton(
		"PLAY",
		buttonXpos + dockerXPadding,
		buttonYpos,
		buttonWidth,
		buttonHeight,
		function() startProgressionPlayback() end
	)
	
	-- STOP button
	self:addSimpleButton(
		"STOP",
		buttonXpos + dockerXPadding + buttonWidth + s(4),
		buttonYpos,
		buttonWidth,
		buttonHeight,
		function() stopProgressionPlayback() end
	)
	
	-- CLEAR button
	self:addSimpleButton(
		"CLEAR",
		buttonXpos + dockerXPadding + (buttonWidth + s(4)) * 2,
		buttonYpos,
		buttonWidth,
		buttonHeight,
		function() clearChordProgression() end
	)
	
	-- SAVE button
	self:addSimpleButton(
		"SAVE",
		buttonXpos + dockerXPadding + (buttonWidth + s(4)) * 3,
		buttonYpos,
		buttonWidth,
		buttonHeight,
		function() saveProgressionPreset() end
	)
	
	-- LOAD button
	self:addSimpleButton(
		"LOAD",
		buttonXpos + dockerXPadding + (buttonWidth + s(4)) * 4,
		buttonYpos,
		buttonWidth,
		buttonHeight,
		function() showLoadPresetMenu() end
	)
	
	-- INSERT button (helemaal rechts uitgelijnd minus ruimte voor help button)
	local totalWidth = self.width - 2 * xMargin - 2 * xPadding
	local helpButtonWidth = s(20)  -- Kleine button voor ?
	local insertButtonX = buttonXpos + dockerXPadding + totalWidth - buttonWidth - helpButtonWidth - s(4)
	self:addSimpleButton(
		"INSERT",
		insertButtonX,
		buttonYpos,
		buttonWidth,
		buttonHeight,
		function() insertProgressionToMIDI() end
	)
	
	-- HELP button (? rechts van INSERT)
	local helpButtonX = insertButtonX + buttonWidth + s(4)
	self:addSimpleButton(
		"?",
		helpButtonX,
		buttonYpos,
		helpButtonWidth,
		buttonHeight,
		function() showHelpWindow() end
	)
end

function Interface:addScaleLabel(xMargin, yMargin, xPadding, yPadding)

	local labelText = "Scale:"
	scaleLabelWidth = gfx.measurestr(labelText) * (gfx.w / baseWidth)
	local labelXpos = xMargin+xPadding
	local labelYpos = yMargin+yPadding
	local labelHeight = s(16)
	self:addLabel(labelXpos+dockerXPadding, labelYpos, scaleLabelWidth, labelHeight, function() return labelText end)
end

function Interface:addScaleTonicNoteDropdown(xMargin, yMargin, xPadding, yPadding, horizontalMargin, scaleTonicNoteWidth)

	local scaleTonicNoteXpos = xMargin+xPadding+scaleLabelWidth+horizontalMargin
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

function Interface:addScaleTypeDropdown(xMargin, yMargin, xPadding, yPadding, horizontalMargin, scaleTonicNoteWidth, scaleTypeWidth)

	local scaleTypeXpos = xMargin+xPadding+scaleLabelWidth+scaleTonicNoteWidth+horizontalMargin*1.5
	local scaleTypeYpos = yMargin+yPadding+s(1)
	local scaleTypeHeight = s(15)

	local onScaleTypeSelection = function(i)

		setScaleType(i)
		setSelectedScaleNote(1)
		setChordText("")
		resetSelectedChordTypes()
		resetChordInversionStates()
		updateScaleData()
		updateScaleDegreeHeaders()
	end
	
	local scaleName = getScaleType()
	self:addDropdown(scaleTypeXpos+dockerXPadding, scaleTypeYpos, scaleTypeWidth, scaleTypeHeight, scaleNames, scaleName, onScaleTypeSelection)
end

function Interface:addScaleNotesTextLabel(xMargin, yMargin, xPadding, yPadding, horizontalMargin, scaleTonicNoteWidth, scaleTypeWidth)

	local getScaleNotesTextCallback = function() return getScaleNotesText() end
	local scaleNotesXpos = xMargin+xPadding+scaleLabelWidth+scaleTonicNoteWidth+scaleTypeWidth+horizontalMargin*2+s(4)
	local scaleNotesYpos = yMargin+yPadding+s(1)
	local scaleNotesWidth = s(360)
	local scaleNotesHeight = s(15)
	self:addLabel(scaleNotesXpos+dockerXPadding, scaleNotesYpos, scaleNotesWidth, scaleNotesHeight, getScaleNotesTextCallback)
end

function Interface:addOctaveLabel(yMargin, yPadding)

	local labelText = "Octave:"
	octaveLabelWidth = gfx.measurestr(labelText) * (gfx.w / baseWidth)
	local labelYpos = yMargin+yPadding+s(1)
	local labelHeight = s(15)
	local octaveValueBoxWidth = s(55)
	local labelXpos = gfx.w - s(80) - octaveValueBoxWidth
	self:addLabel(labelXpos+dockerXPadding, labelYpos, octaveLabelWidth, labelHeight, function() return labelText end)
end

function Interface:addOctaveSelectorValueBox(yMargin, xMargin, xPadding, octaveValueBoxWidth)

	local valueBoxXPos = gfx.w - octaveValueBoxWidth - xMargin - xPadding + s(3)
	local valueBoxYPos = yMargin + s(6)
	local valueBoxHeight = s(15)
	self:addOctaveValueBox(valueBoxXPos+dockerXPadding, valueBoxYPos, octaveValueBoxWidth, valueBoxHeight)
end
local workingDirectory = reaper.GetResourcePath() .. "/Scripts/ChordGun/src"

-- Deze variabelen worden binnen functies lokaal gedefinieerd om scaling issues te voorkomen
-- local xMargin = s(8)
-- local yMargin = s(8) + keySelectionFrameHeight + s(6)
-- local xPadding = s(7)
-- local yPadding = s(30)
-- local headerHeight = s(25)
-- local inversionLabelWidth = s(80)
-- local inversionValueBoxWidth = s(55)

local chordTextWidth = nil

function Interface:addBottomFrame()

	-- Definieer lokaal zodat ze correct schalen
	local xMargin = s(8)
	local yMargin = s(8) + (self.keySelectionFrameHeight or s(25)) + s(6)
	local xPadding = s(7)
	local yPadding = s(30)
	local headerHeight = s(25)
	local inversionLabelWidth = s(80)
	local inversionValueBoxWidth = s(55)

	local chordButtonsFrameHeight = self.height - yMargin - s(6)
	self:addFrame(xMargin+dockerXPadding, yMargin, self.width - 2 * xMargin, chordButtonsFrameHeight)
  
  self:addHoldButton(xMargin, yMargin, xPadding)
  self:addKillButton(xMargin, yMargin, xPadding)
  self:addStrumButton(xMargin, yMargin, xPadding)
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
  local chordTextYpos = yMargin + s(4)
  chordTextWidth = self.width - 4 * xMargin - inversionLabelWidth - inversionValueBoxWidth - s(6)
  local chordTextHeight = s(24)
  self:addLabel(chordTextXpos+dockerXPadding, chordTextYpos, chordTextWidth, chordTextHeight, getChordTextCallback)
end

function Interface:addInversionLabel(xMargin, yMargin, xPadding)

  local inversionLabelText = "Inversion:"
  local inversionLabelXPos = xMargin + xPadding + chordTextWidth
  local inversionLabelYPos = yMargin + s(4)
  local stringWidth, _ = gfx.measurestr(labelText)
  local inversionLabelTextHeight = s(24)
  local inversionLabelWidth = s(80)

  self:addLabel(inversionLabelXPos+dockerXPadding, inversionLabelYPos, inversionLabelWidth, inversionLabelTextHeight, function() return inversionLabelText end)
end

function Interface:addInversionValueBox(xMargin, yMargin, xPadding, inversionLabelWidth)

  local inversionValueBoxWidth = s(55)
  local inversionValueBoxXPos = xMargin + xPadding + chordTextWidth + inversionLabelWidth + s(2)
  local inversionValueBoxYPos = yMargin + s(9)
  local inversionValueBoxHeight = s(15)
  self:addChordInversionValueBox(inversionValueBoxXPos+dockerXPadding, inversionValueBoxYPos, inversionValueBoxWidth, inversionValueBoxHeight)
end

function Interface:addHeaders(xMargin, yMargin, xPadding, yPadding, headerHeight)
  
  for i = 1, #scaleNotes do

    local headerWidth = s(104)
    local innerSpacing = s(2)

    local headerXpos = xMargin+xPadding-s(1) + headerWidth * (i-1) + innerSpacing * i
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

      	local buttonWidth = s(104)
      	local buttonHeight = s(38)
				local innerSpacing = s(2)
      	
      	local xPos = xMargin + xPadding + buttonWidth * (scaleNoteIndex-1) + innerSpacing * scaleNoteIndex + dockerXPadding
      	local yPos = yMargin + yPadding + headerHeight + buttonHeight * (chordTypeIndex-1) + innerSpacing * (chordTypeIndex-1) - s(3)
  
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

-- Load and apply saved UI scale before initializing interface
local savedScaleIndex = getUiScaleIndex()
applyUiScale(savedScaleIndex)

interfaceWidth = getInterfaceWidth()
interfaceHeight = getInterfaceHeight()

updateScaleData()

local interface = Interface:init("CHORDGUN (TK MOD)")
interface:startGui()

local function windowHasNotBeenClosed()
	return inputCharacter ~= -1
end

local function main()

	if gfx.w ~= interface.lastWidth or gfx.h ~= interface.lastHeight then
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

	if windowHasNotBeenClosed() then
		reaper.runloop(main)
	end
	
	interface:update()
end

main()


-- If you want the ChordGun window to always be on top then do the following things:
--
-- 1. install julian sader extension https://forum.cockos.com/showthread.php?t=212174
--
-- 2. uncomment the following code:
--
-- 		if (reaper.JS_Window_Find) then
-- 			local hwnd = reaper.JS_Window_Find("ChordGun", true)
-- 			reaper.JS_Window_SetZOrder(hwnd, "TOPMOST", hwnd)
-- 		end
--
--
--
-- Note that this only works on Windows machines
