-- @noindex
-- Data file for TK ChordGun and its helper scripts

local Data = {}

Data.notes = { 'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B' }
Data.flatNotes = { 'C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B' }

Data.chords = {
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
    name = 'half-diminished seventh',
    code = 'm7b5',
    display = 'm7b5',
    pattern = '10010010001'
  },
  {
    name = 'diminished seventh',
    code = 'dim7',
    display = 'dim7',
    pattern = '1001001001'
  },
  -- Extended Chords (Added in v2.3.1)
  {name="add9",   code="add9",   pattern="101010010000", display="add9"},
  {name="6/9",    code="6/9",    pattern="101010000100", display="6/9"},
  {name="maj9",   code="maj9",   pattern="101010010001", display="maj9"},
  {name="min9",   code="min9",   pattern="100100010010", display="m9"},
  {name="9",      code="9",      pattern="100010010010", display="9"},
  {name="7b9",    code="7b9",    pattern="110010010010", display="7b9"},
  {name="7#9",    code="7#9",    pattern="100110010010", display="7#9"},
  {name="11",     code="11",     pattern="100011010010", display="11"},
  {name="min11",  code="min11",  pattern="100101010010", display="m11"},
  {name="maj#11", code="maj#11", pattern="100010110001", display="maj#11"},
  {name="13",     code="13",     pattern="100010010110", display="13"},
  {name="maj13",  code="maj13",  pattern="100010010101", display="maj13"},
  {name="min13",  code="min13",  pattern="100100010110", display="m13"},
  {name="sus4b9", code="sus4b9", pattern="110001010000", display="sus4b9"},
  {
    name = 'augmented major seventh',
    code = 'augMaj7',
    display = '+maj7',
    pattern = '100010001001'
  },
  {
    name = 'flat fifth',
    code = 'flat5',
    display = '5-',
    pattern = '10000010'
  },
  -- Dyads (Added in v2.3.8 - IDM/Ambient)
  {name="perfect fourth", code="4th", display="4", pattern="100001"},
  {name="minor third", code="m3", display="m3", pattern="1001"},
  {name="major third", code="M3", display="M3", pattern="10001"},
  {name="minor second", code="m2", display="m2", pattern="11"},
  {name="major second", code="M2", display="M2", pattern="101"},
  {name="minor sixth", code="m6", display="m6", pattern="100000001"},
  {name="major sixth", code="M6", display="M6", pattern="1000000001"},
  {name="minor seventh", code="m7", display="m7int", pattern="10000000001"},
  {name="major seventh", code="M7", display="M7int", pattern="100000000001"},
  -- Stacked Fifths (BoC-style)
  {name="stacked fifths", code="55", display="5/5", pattern="1000000100000001"},
  {name="sus2 stacked", code="sus2stack", display="sus2/5", pattern="10100001000000100000001"},
}

local function parseReascaleFile(filePath)
  local file = io.open(filePath, "r")
  if not file then return nil end
  
  local importedScales = {}
  
  for line in file:lines() do
    -- Check for Header (starts with 2)
    local headerName = line:match('^%s*2%s+"(.-)"')
    if headerName then
      table.insert(importedScales, {
        name = "--- " .. headerName .. " ---",
        pattern = "000000000000", -- Empty pattern
        isHeader = true,
        description = "Category: " .. headerName
      })
    else
      -- Match lines with ID, Name, and Pattern (allowing digits 0-9 in pattern)
      local name, pattern = line:match('^%s*%d+%s+"(.-)"%s+([0-9]+)')
      
      if name and pattern and #pattern == 12 then
        -- Convert any non-zero digit to '1' to ensure compatibility with ChordGun logic
        pattern = pattern:gsub("[2-9]", "1")
        
        table.insert(importedScales, {
          name = name,
          pattern = pattern,
          isCustom = true,
          description = "Imported from .reascale file"
        })
      end
    end
  end
  
  file:close()
  return importedScales
end

local function loadUserReascales(systemTable)
  -- Gebruik absoluut pad via ResourcePath, net als bij Presets
  local reascaleDir = reaper.GetResourcePath() .. "/Scripts/TK Scripts/Midi/TK_ChordGun/Reascales"
  
  -- Zorg voor correcte slashes op Windows
  if reaper.GetOS():match("Win") then
    reascaleDir = reascaleDir:gsub("/", "\\")
  end
  
  -- Maak map aan
  reaper.RecursiveCreateDirectory(reascaleDir, 0)
  
  local i = 0
  while true do
    local file = reaper.EnumerateFiles(reascaleDir, i)
    if not file then break end
    
    if file:match("%.reascale$") then
      local fullPath = reascaleDir .. "/" .. file
      -- Fix path separator voor parse functie
      if reaper.GetOS():match("Win") then fullPath = reascaleDir .. "\\" .. file end
      
      local userScales = parseReascaleFile(fullPath)
      
      if userScales and #userScales > 0 then
        local systemName = file:gsub("%.reascale$", "") .. " (User)"
        table.insert(systemTable, {
          name = systemName,
          scales = userScales
        })
      end
    end
    i = i + 1
  end
end

Data.scaleSystems = {
  {
    name = "Diatonic",
    scales = {
      { name = "Major", pattern = "101011010101", 
        description = "Heptatonic (7 notes) - Bright, happy sound\nMost common scale in Western music" },
      { name = "Natural Minor", pattern = "101101011010",
        description = "Heptatonic (7 notes) - Dark, sad sound\nRelative minor of Major scale" },
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
    name = "Harmonic Minor Modes",
    scales = {
      { name = "Harmonic Minor", pattern = "101101011001",
        description = "Mode 1: Aeolian #7\nDark, exotic, classical/metal\n1 2 b3 4 5 b6 7" },
      { name = "Locrian #6", pattern = "110101100101",
        description = "Mode 2: Locrian natural 6\nDark, diminished quality\n1 b2 b3 4 b5 6 b7" },
      { name = "Ionian #5", pattern = "101011001011",
        description = "Mode 3: Ionian Augmented\nDreamy, unsettled major\n1 2 3 4 #5 6 7" },
      { name = "Dorian #4", pattern = "101100110101",
        description = "Mode 4: Dorian #11\nBluesy minor with sharp 4\n1 2 b3 #4 5 6 b7" },
      { name = "Phrygian Dominant", pattern = "110011011010",
        description = "Mode 5: Phrygian Major\nSpanish, Flamenco, Metal\n1 b2 3 4 5 b6 b7" },
      { name = "Lydian #2", pattern = "100110110101",
        description = "Mode 6: Lydian sharp 2\nBright, angular, modern\n1 #2 3 #4 5 6 7" },
      { name = "Super Locrian bb7", pattern = "110101011001",
        description = "Mode 7: Altered bb7 / Ultralocrian\nDiminished, very dissonant\n1 b2 b3 b4 b5 b6 bb7" }
    }
  },
  {
    name = "Melodic Minor Modes",
    scales = {
      { name = "Melodic Minor", pattern = "101101010101",
        description = "Mode 1: Jazz Minor / Ionian b3\nAscending Melodic Minor\n1 2 b3 4 5 6 7" },
      { name = "Dorian b2", pattern = "110101010101",
        description = "Mode 2: Phrygian #6\nDark minor with natural 6\n1 b2 b3 4 5 6 b7" },
      { name = "Lydian Augmented", pattern = "101010101101",
        description = "Mode 3: Lydian #5\nDreamy, whole-tone feel\n1 2 3 #4 #5 6 7" },
      { name = "Lydian Dominant", pattern = "101010110101",
        description = "Mode 4: Lydian b7 / Overtone\nAcoustic scale, bright dominant\n1 2 3 #4 5 6 b7" },
      { name = "Mixolydian b6", pattern = "101011011010",
        description = "Mode 5: Hindu / Aeolian Dominant\nMelodic major/minor hybrid\n1 2 3 4 5 b6 b7" },
      { name = "Locrian #2", pattern = "101101101010",
        description = "Mode 6: Aeolian b5 / Half-Diminished\nDark, jazzy minor\n1 2 b3 4 b5 b6 b7" },
      { name = "Super Locrian", pattern = "110110101010",
        description = "Mode 7: Altered Scale\nDominant altered tensions\n1 b2 b3 b4 b5 b6 b7" }
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

      { name = "Mode 1.1", pattern = "101010101010", isCustom = true, intervals = "2-2-2-2-2-2",
        description = "Hexatonic (6 notes) - Whole Tone Scale\n1st transposition | Dreamy, floating\nDebussy's favorite" },
      { name = "Mode 1.2", pattern = "010101010101", isCustom = true, intervals = "2-2-2-2-2-2",
        description = "Hexatonic (6 notes) - Whole Tone Scale\n2nd transposition | The 'other' whole tone set\nCompletes the chromatic coverage" },
      

      { name = "Mode 2.1", pattern = "110110110110", isCustom = true, intervals = "1-2-1-2-1-2-1-2",
        description = "Octatonic (8 notes) - Half-Whole Diminished\n1st transposition (Starts on C)\nJazz/classical favorite" },
      { name = "Mode 2.2", pattern = "011011011011", isCustom = true, intervals = "1-2-1-2-1-2-1-2",
        description = "Octatonic (8 notes) - Half-Whole Diminished\n2nd transposition (Starts on C#)\nShifted up 1 semitone" },
      { name = "Mode 2.3", pattern = "101101101101", isCustom = true, intervals = "1-2-1-2-1-2-1-2",
        description = "Octatonic (8 notes) - Half-Whole Diminished\n3rd transposition (Starts on D)\nShifted up 2 semitones" },
      

      { name = "Mode 3.1", pattern = "101110111011", isCustom = true, intervals = "2-1-1-2-1-1-2-1-1",
        description = "Nonatonic (9 notes) - Dense, chromatic\n1st transposition | Repeating 2-1-1 pattern\nVery colorful" },
      { name = "Mode 3.2", pattern = "110111011101", isCustom = true, intervals = "2-1-1-2-1-1-2-1-1",
        description = "Nonatonic (9 notes) - Dense, chromatic\n2nd transposition | Shifted up 1 semitone\nUsed in 'Quartet for the End of Time'" },
      { name = "Mode 3.3", pattern = "111011101110", isCustom = true, intervals = "2-1-1-2-1-1-2-1-1",
        description = "Nonatonic (9 notes) - Dense, chromatic\n3rd transposition | Shifted up 2 semitones\nHighly symmetrical" },
      { name = "Mode 3.4", pattern = "011101110111", isCustom = true, intervals = "2-1-1-2-1-1-2-1-1",
        description = "Nonatonic (9 notes) - Dense, chromatic\n4th transposition | Shifted up 3 semitones\nRich harmonic palette" },
      

      { name = "Mode 4.1", pattern = "111001111001", isCustom = true, intervals = "1-1-3-1-1-1-3-1",
        description = "Octatonic (8 notes) - Exotic, Eastern flavor\nRepeating 1-1-3-1 pattern | 1st transposition\nUsed for mysterious, otherworldly sounds" },
      { name = "Mode 4.2", pattern = "111100111100", isCustom = true, intervals = "1-3-1-1-1-3-1-1",
        description = "Octatonic (8 notes) - Exotic, Eastern flavor\n2nd transposition | Alternating small/large gaps\nPopular in film scores" },
      { name = "Mode 4.3", pattern = "011110011110", isCustom = true, intervals = "3-1-1-1-3-1-1-1",
        description = "Octatonic (8 notes) - Exotic, Eastern flavor\n3rd transposition | Creates tension and release\nContains augmented and minor triads" },
      { name = "Mode 4.4", pattern = "001111001111", isCustom = true, intervals = "1-1-1-3-1-1-1-3",
        description = "Octatonic (8 notes) - Exotic, Eastern flavor\n4th transposition | Clusters and wide leaps\nUseful for dramatic moments" },
      { name = "Mode 4.5", pattern = "100111100111", isCustom = true, intervals = "1-1-3-1-1-1-3-1",
        description = "Octatonic (8 notes) - Exotic, Eastern flavor\n5th transposition | Repeating pattern\nSymmetrical structure" },
      { name = "Mode 4.6", pattern = "110011110011", isCustom = true, intervals = "1-1-3-1-1-1-3-1",
        description = "Octatonic (8 notes) - Exotic, Eastern flavor\n6th and final transposition of Mode 4\nComplete the symmetrical cycle" },
      

      { name = "Mode 5.1", pattern = "110001110001", isCustom = true, intervals = "1-4-1-1-4-1",
        description = "Hexatonic (6 notes) - Wide intervals, sparse\nRepeating 1-4-1 pattern | 1st transposition\nOpen, spacious sound with dramatic leaps" },
      { name = "Mode 5.2", pattern = "111000111000", isCustom = true, intervals = "4-1-1-4-1-1",
        description = "Hexatonic (6 notes) - Wide intervals, sparse\n2nd transposition | Major 3rd leaps\nUsed for ethereal, floating textures" },
      { name = "Mode 5.3", pattern = "011100011100", isCustom = true, intervals = "1-1-4-1-1-4",
        description = "Hexatonic (6 notes) - Wide intervals, sparse\n3rd transposition | Alternating gaps\nCreates sense of space and distance" },
      { name = "Mode 5.4", pattern = "001110001110", isCustom = true, intervals = "1-4-1-1-4-1",
        description = "Hexatonic (6 notes) - Wide intervals, sparse\n4th transposition | Pentatonic-like\nUseful for minimalist compositions" },
      { name = "Mode 5.5", pattern = "000111000111", isCustom = true, intervals = "4-1-1-4-1-1",
        description = "Hexatonic (6 notes) - Wide intervals, sparse\n5th transposition | Symmetrical gaps\nCreates mysterious atmosphere" },
      { name = "Mode 5.6", pattern = "100011100011", isCustom = true, intervals = "1-1-4-1-1-4",
        description = "Hexatonic (6 notes) - Wide intervals, sparse\n6th and final transposition of Mode 5\nCompletes the hexatonic cycle" },
      

      { name = "Mode 6.1", pattern = "101011101011", isCustom = true, intervals = "2-2-1-1-2-2-1-1",
        description = "Octatonic (8 notes) - Balanced, versatile\nRepeating 2-2-1-1 pattern | 1st transposition\nBlends whole tone and chromatic elements" },
      { name = "Mode 6.2", pattern = "110101110101", isCustom = true, intervals = "2-1-1-2-2-1-1-2",
        description = "Octatonic (8 notes) - Balanced, versatile\n2nd transposition | Smooth motion\nUseful for melodic lines" },
      { name = "Mode 6.3", pattern = "111010111010", isCustom = true, intervals = "1-1-2-2-1-1-2-2",
        description = "Octatonic (8 notes) - Balanced, versatile\n3rd transposition | Paired intervals\nCreates interesting harmonic progressions" },
      { name = "Mode 6.4", pattern = "011101011101", isCustom = true, intervals = "1-2-2-1-1-2-2-1",
        description = "Octatonic (8 notes) - Balanced, versatile\n4th transposition | Alternating pairs\nGood for both melody and harmony" },
      { name = "Mode 6.5", pattern = "101110101110", isCustom = true, intervals = "2-1-1-2-2-1-1-2",
        description = "Octatonic (8 notes) - Balanced, versatile\n5th transposition | Symmetrical structure\nUsed in Messiaen's piano works" },
      { name = "Mode 6.6", pattern = "010111010111", isCustom = true, intervals = "1-2-2-1-1-2-2-1",
        description = "Octatonic (8 notes) - Balanced, versatile\n6th and final transposition of Mode 6\nCompletes the octave division" },
      

      { name = "Mode 7.1", pattern = "111101111101", isCustom = true, intervals = "1-1-1-2-1-1-1-1-2-1",
        description = "Decatonic (10 notes) - Most chromatic\nRepeating 1-1-1-2-1 pattern | 1st transposition\nAlmost all 12 chromatic notes - highly dissonant" },
      { name = "Mode 7.2", pattern = "111011111011", isCustom = true, intervals = "1-1-2-1-1-1-1-2-1-1",
        description = "Decatonic (10 notes) - Most chromatic\n2nd transposition | Dense clusters\nUsed for intense, dramatic moments" },
      { name = "Mode 7.3", pattern = "110111110111", isCustom = true, intervals = "1-2-1-1-1-1-2-1-1-1",
        description = "Decatonic (10 notes) - Most chromatic\n3rd transposition | Maximum color\nMessiaen's most complex mode" },
      { name = "Mode 7.4", pattern = "101111101111", isCustom = true, intervals = "2-1-1-1-1-2-1-1-1-1",
        description = "Decatonic (10 notes) - Most chromatic\n4th transposition | Chromatic saturation\nUseful for avant-garde compositions" },
      { name = "Mode 7.5", pattern = "111110111110", isCustom = true, intervals = "1-1-1-1-2-1-1-1-2-1",
        description = "Decatonic (10 notes) - Most chromatic\n5th transposition | Dense harmony\nContains nearly every possible chord type" },
      { name = "Mode 7.6", pattern = "111011110111", isCustom = true, intervals = "1-1-2-1-1-1-2-1-1-1",
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
      { name = "Harmonic Major", pattern = "101011011001", isCustom = true, intervals = "2-2-1-2-1-3-1",
        description = "Heptatonic (7 notes) - Major with b6\nMajor scale with flattened 6th\nExotic sound, used in jazz and metal" }
    }
  },
  {
    name = "World Music",
    scales = {
      { name = "Hijaz", pattern = "11001101010", isCustom = true, intervals = "1-3-1-2-1-2-2",
        description = "Heptatonic (7 notes) - Arabic Maqam\nDramatic augmented 2nd interval | Middle Eastern flavor\nUsed in Arabic, Turkish, Greek, and Klezmer music" },
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
      { name = "Neapolitan Minor", pattern = "11010100110", isCustom = true, intervals = "1-2-2-2-1-3-1",
        description = "Heptatonic (7 notes) - Dark, exotic minor\nMinor with flattened 2nd | Dramatic\nSymphonic metal, film scores" },
      { name = "Neapolitan Major", pattern = "11010110010", isCustom = true, intervals = "1-2-2-2-2-2-1",
        description = "Heptatonic (7 notes) - Bright yet exotic\nMajor with flattened 2nd | Unusual\nProgressive rock/metal, experimental" },
      { name = "Hungarian Major", pattern = "10011011010", isCustom = true, intervals = "3-1-2-1-2-1-2",
        description = "Heptatonic (7 notes) - Exotic major sound\nLydian with flat 6 and 7 | Augmented 2nd\nGypsy-flavored rock, folk metal" }
    }
  }
}

-- Load user custom scales from .reascale files
loadUserReascales(Data.scaleSystems)

Data.scales = {}
for _, system in ipairs(Data.scaleSystems) do
  for _, scale in ipairs(system.scales) do
    table.insert(Data.scales, scale)
  end
end

Data.progressionTemplates = {
  {
    name = "Pop / Rock",
    minNotes = 7,
    progressions = {
      { name = "Axis of Awesome (I-V-vi-IV)", chords = {1, 5, 6, 4} },
      { name = "50s (I-vi-IV-V)", chords = {1, 6, 4, 5} },
      { name = "Sensitive (vi-IV-I-V)", chords = {6, 4, 1, 5} },
      { name = "Pachelbel (I-V-vi-iii-IV-I-IV-V)", chords = {1, 5, 6, 3, 4, 1, 4, 5} },
      { name = "Andalusian (vi-V-IV-III)", chords = {6, 5, 4, 3} },
      { name = "Singer-Songwriter (I-IV-I-V)", chords = {1, 4, 1, 5} },
      { name = "Rock Anthem (I-IV-V-IV)", chords = {1, 4, 5, 4} },
      { name = "Ballad (I-V-vi-IV-I-V-iii-IV)", chords = {1, 5, 6, 4, 1, 5, 3, 4} }
    }
  },
  {
    name = "Jazz",
    minNotes = 7,
    progressions = {
      { name = "ii-V-I", chords = {2, 5, 1} },
      { name = "I-vi-ii-V (Turnaround)", chords = {1, 6, 2, 5} },
      { name = "iii-vi-ii-V (Extended)", chords = {3, 6, 2, 5} },
      { name = "I-IV-iii-vi (Jazzy)", chords = {1, 4, 3, 6} },
      { name = "ii-V-I-vi", chords = {2, 5, 1, 6} },
      { name = "I-ii-iii-IV-V", chords = {1, 2, 3, 4, 5} },
      { name = "Autumn Leaves (ii-V-I-IV-vii-iii-vi)", chords = {2, 5, 1, 4, 7, 3, 6} },
      { name = "Rhythm Changes A (I-vi-ii-V-I-vi-ii-V)", chords = {1, 6, 2, 5, 1, 6, 2, 5} }
    }
  },
  {
    name = "Blues",
    minNotes = 5,
    progressions = {
      { name = "12-Bar Blues (I-I-I-I-IV-IV-I-I)", chords = {1, 1, 1, 1, 4, 4, 1, 1} },
      { name = "Quick Change (I-IV-I-I-IV-IV-I-I)", chords = {1, 4, 1, 1, 4, 4, 1, 1} },
      { name = "8-Bar Blues (I-V-IV-IV-I-V-I-V)", chords = {1, 5, 4, 4, 1, 5, 1, 5} },
      { name = "Minor Blues (i-i-i-i-iv-iv-i-i)", chords = {1, 1, 1, 1, 4, 4, 1, 1} },
      { name = "Jazz Blues (I-IV-I-I-IV-IV-I-vi-ii-V-I-V)", chords = {1, 4, 1, 1, 4, 4, 1, 6} }
    }
  },
  {
    name = "Classical",
    minNotes = 7,
    progressions = {
      { name = "Authentic Cadence (IV-V-I)", chords = {4, 5, 1} },
      { name = "Plagal Cadence (IV-I)", chords = {4, 1} },
      { name = "Circle of Fifths (I-IV-vii-iii-vi-ii-V-I)", chords = {1, 4, 7, 3, 6, 2, 5, 1} },
      { name = "Romanesca (III-VII-i-V)", chords = {3, 7, 1, 5} },
      { name = "Passamezzo Antico (i-VII-i-V-III-VII-i-V-i)", chords = {1, 7, 1, 5, 3, 7, 1, 5} },
      { name = "La Folia (i-V-i-VII-III-VII-i-V)", chords = {1, 5, 1, 7, 3, 7, 1, 5} }
    }
  },
  {
    name = "Modal: Dorian",
    minNotes = 7,
    scaleHint = "Dorian",
    progressions = {
      { name = "Dorian Vamp (i-IV)", chords = {1, 4} },
      { name = "So What (i-IV-i-IV)", chords = {1, 4, 1, 4} },
      { name = "Dorian Funk (i-IV-v-IV)", chords = {1, 4, 5, 4} },
      { name = "Dorian Jazz (i-ii-IV-i)", chords = {1, 2, 4, 1} }
    }
  },
  {
    name = "Modal: Mixolydian",
    minNotes = 7,
    scaleHint = "Mixolydian",
    progressions = {
      { name = "Mixo Rock (I-bVII-IV-I)", chords = {1, 7, 4, 1} },
      { name = "Sweet Home (I-bVII-IV)", chords = {1, 7, 4} },
      { name = "Mixo Groove (I-IV-bVII-IV)", chords = {1, 4, 7, 4} },
      { name = "Hey Joe (I-IV-I-V-IV-I)", chords = {1, 4, 1, 5, 4, 1} }
    }
  },
  {
    name = "Modal: Phrygian",
    minNotes = 7,
    scaleHint = "Phrygian",
    progressions = {
      { name = "Phrygian Vamp (i-bII)", chords = {1, 2} },
      { name = "Flamenco (i-bII-bIII-bII)", chords = {1, 2, 3, 2} },
      { name = "Metal Phrygian (i-bII-i-bVII)", chords = {1, 2, 1, 7} },
      { name = "Spanish (i-bVII-bVI-V)", chords = {1, 7, 6, 5} }
    }
  },
  {
    name = "Minor Keys",
    minNotes = 7,
    progressions = {
      { name = "Aeolian (i-VI-III-VII)", chords = {1, 6, 3, 7} },
      { name = "Epic Minor (i-VII-VI-VII)", chords = {1, 7, 6, 7} },
      { name = "Dramatic (i-iv-V-i)", chords = {1, 4, 5, 1} },
      { name = "Minor Ballad (i-VI-III-VII-i-VI-iv-V)", chords = {1, 6, 3, 7, 1, 6, 4, 5} },
      { name = "Neo-Classical (i-V-VI-III-iv-i-iv-V)", chords = {1, 5, 6, 3, 4, 1, 4, 5} },
      { name = "Harmonic Minor (i-iv-V-i-VI-III-iv-V)", chords = {1, 4, 5, 1, 6, 3, 4, 5} }
    }
  },
  {
    name = "EDM / Electronic",
    minNotes = 5,
    progressions = {
      { name = "Trance Gate (i-VI-III-VII)", chords = {1, 6, 3, 7} },
      { name = "House (i-i-VI-VII)", chords = {1, 1, 6, 7} },
      { name = "Epic Build (VI-VII-i-i)", chords = {6, 7, 1, 1} },
      { name = "Progressive (i-VI-i-VII)", chords = {1, 6, 1, 7} },
      { name = "Future Bass (I-vi-IV-V)", chords = {1, 6, 4, 5} },
      { name = "Minimal (i-IV-i-IV)", chords = {1, 4, 1, 4} }
    }
  },
  {
    name = "World / Folk",
    minNotes = 5,
    progressions = {
      { name = "Celtic (I-VII-VI-VII)", chords = {1, 7, 6, 7} },
      { name = "Irish Reel (I-V-vi-IV-I-V-I-V)", chords = {1, 5, 6, 4, 1, 5, 1, 5} },
      { name = "Klezmer (i-IV-V-i)", chords = {1, 4, 5, 1} },
      { name = "Flamenco Cadence (iv-III-II-I)", chords = {4, 3, 2, 1} },
      { name = "Arabic (i-bII-i-V)", chords = {1, 2, 1, 5} }
    }
  },
  {
    name = "Reggae / Dub",
    minNotes = 5,
    progressions = {
      { name = "One Drop (I-IV)", chords = {1, 4, 1, 4, 1, 4, 1, 4} },
      { name = "Roots Rock (I-V)", chords = {1, 5, 1, 5, 1, 5, 1, 5} },
      { name = "Steppers (I-IV-V-IV)", chords = {1, 1, 4, 4, 5, 5, 4, 4} },
      { name = "Ska Bounce (I-IV-V-IV)", chords = {1, 4, 5, 4, 1, 4, 5, 4} },
      { name = "Dub Plate (i-iv)", chords = {1, 4, 1, 4, 1, 4, 1, 4} },
      { name = "Rub-a-Dub (i-VII-VI-VII)", chords = {1, 7, 6, 7, 1, 7, 6, 7} },
      { name = "Rockers (i-iv-V-iv)", chords = {1, 4, 5, 4, 1, 4, 5, 4} },
      { name = "Black Uhuru Style (I-IV-I-IV)", chords = {1, 4, 1, 4} },
      { name = "Sly & Robbie (i-iv-i-V)", chords = {1, 4, 1, 5, 1, 4, 1, 5} },
      { name = "Roots Radics (i-VII-i-iv)", chords = {1, 7, 1, 4, 1, 7, 1, 4} },
      { name = "King Tubby (I-IV-V-I)", chords = {1, 4, 5, 1, 1, 4, 5, 1} },
      { name = "Lee Perry (i-III-iv-VII)", chords = {1, 3, 4, 7, 1, 3, 4, 7} },
      { name = "Nyabinghi (I-IV-I-V-IV-I)", chords = {1, 4, 1, 5, 4, 1} },
      { name = "Lover's Rock (I-vi-IV-V)", chords = {1, 6, 4, 5, 1, 6, 4, 5} },
      { name = "Dancehall (i-iv-VII-III)", chords = {1, 4, 7, 3, 1, 4, 7, 3} },
      { name = "Dub Siren (i-VII)", chords = {1, 7, 1, 7, 1, 7, 1, 7} }
    }
  },
  {
    name = "IDM / Ambient",
    minNotes = 5,
    progressions = {
      { name = "BoC: Pete Standing Alone (I-IV-V-I)", chords = {1, 4, 5, 1}, chordType = "5" },
      { name = "BoC: Chromakey Dreamcoat (I-II-IV-V)", chords = {1, 2, 4, 5}, chordType = "sus2" },
      { name = "BoC: Everything You Do (I-IV-I-V)", chords = {1, 4, 1, 5}, chordType = "m3" },
      { name = "BoC: Cold Earth (I-IV)", chords = {1, 4}, chordType = "5" },
      { name = "BoC: Under The Coke Sign (I-IV-I)", chords = {1, 4, 1}, chordType = "5" },
      { name = "Ambient Fifths (I-V-IV-I)", chords = {1, 5, 4, 1}, chordType = "5" },
      { name = "Ambient Fourths (I-IV-VII-IV)", chords = {1, 4, 7, 4}, chordType = "4" },
      { name = "Stacked Fifths (I-IV-V-IV)", chords = {1, 4, 5, 4}, chordType = "55" },
      { name = "Warp Records (i-VI-III-VII)", chords = {1, 6, 3, 7} },
      { name = "Autechre Style (i-ii-IV-III)", chords = {1, 2, 4, 3} },
      { name = "Aphex Ambient (I-III-V-IV)", chords = {1, 3, 5, 4} },
      { name = "Floating (I-V-I-IV)", chords = {1, 5, 1, 4}, chordType = "sus2" },
      { name = "Ethereal (i-VII-VI-III)", chords = {1, 7, 6, 3} },
      { name = "Nostalgic (I-vi-IV-I)", chords = {1, 6, 4, 1} },
      { name = "Lo-Fi Drift (i-IV-i-VII)", chords = {1, 4, 1, 7} },
      { name = "Campfire Headphase (I-IV-V-I-IV-I)", chords = {1, 4, 5, 1, 4, 1}, chordType = "sus2" }
    }
  }
}

return Data
