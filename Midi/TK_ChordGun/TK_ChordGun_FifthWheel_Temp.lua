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
