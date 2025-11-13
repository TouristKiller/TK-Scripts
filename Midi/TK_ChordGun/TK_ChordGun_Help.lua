-- ChordGun Help Window (separate script)
-- This runs as a separate gfx instance

local helpLines = {
	"CHORDGUN (TK MOD) - HELP",
	"",
	"=== SCALE & KEY SELECTION ===",
	"• Scale dropdown: Select root note (C, C#, D, etc.)",
	"• Scale Type dropdown: Choose scale type (Major, Minor, etc.)",
	"• Ctrl + ,/.: Navigate scale root note",
	"• Ctrl + </>: Navigate scale type",
	"",
	"=== OCTAVE CONTROL ===",
	"• Octave value box arrows: Click left/right to change octave",
	"• Alt + ,/.: Decrease/increase octave",
	"• Alt + </> (Mac): Decrease/increase octave",
	"",
	"=== CHORD INVERSION ===",
	"• Inversion value box arrows:",
	"  - Click: Preview inversion change",
	"  - Shift + Click: Insert with new inversion",
	"• Cmd/Ctrl + ,/.: Navigate inversions",
	"• Cmd/Ctrl + </> (Mac): Navigate inversions",
	"",
	"=== CHORD BUTTONS (I - vii°) ===",
	"• Click: Preview chord (plays notes)",
	"• Shift + Click: Insert chord at cursor position",
	"• Alt + Click: Add chord to progression slot",
	"• Right Click: Stop all playing notes",
	"• Hold & drag: Continuous preview (works with HOLD mode)",
	"",
	"=== CHORD TYPE SELECTION ===",
	"• Click chord button: Preview/insert",
	"• Cmd/Ctrl + ,/.: Cycle through chord types for selected scale degree",
	"",
	"=== PLAYBACK CONTROLS ===",
	"• HOLD button:",
	"  - Click: Toggle hold mode (notes continue after mouse release)",
	"• KILL button: Stop all playing notes immediately",
	"• STRUM button:",
	"  - Click: Toggle strum mode (arpeggiates notes)",
	"  - Ctrl + Click: Adjust strum delay (10-500ms)",
	"• Scale button (1.0x/1.5x/2.0x):",
	"  - Click: Cycle UI scale size",
	"",
	"=== CHORD PROGRESSION ===",
	"Progression Slots:",
	"• Click empty slot: Select for Alt+Click chord assignment",
	"• Click selected slot: Deselect",
	"• Ctrl + Click filled slot: Edit beats (1/2/4/8) and repeats (1-4)",
	"• Shift + Click slot: Set as loop endpoint (orange marker)",
	"• Alt + Right Click: Clear slot",
	"",
	"Progression Controls:",
	"• PLAY: Start progression playback",
	"• STOP: Stop progression playback",
	"• CLEAR: Clear all progression slots",
	"• SAVE: Save current progression as preset",
	"• LOAD: Select preset from menu to load / Delete option in submenu",
	"• INSERT: Insert entire progression as MIDI notes at cursor",
	"",
	"=== KEYBOARD SHORTCUTS (Scale Degrees 1-7) ===",
	"Preview (lowercase):",
	"• a s d f g h j: Preview scale notes (current octave)",
	"• z x c v b n m: Preview scale notes (lower octave)",
	"• q w e r t y u: Preview scale notes (higher octave)",
	"• 1 2 3 4 5 6 7: Preview chords",
	"",
	"Insert (uppercase/shift):",
	"• A S D F G H J: Insert scale notes (current octave)",
	"• Z X C V B N M: Insert scale notes (lower octave)",
	"• Q W E R T Y U: Insert scale notes (higher octave)",
	"• ! @ # $ % ^ &: Insert chords",
	"",
	"Other Keys:",
	"• 0 / Middle Mouse: Stop all notes",
	"• ESC: Close window",
	"• Left/Right Arrow: Move cursor by grid",
	"• Alt + ,/.: Halve/double grid size",
	"",
	"=== PIANO KEYBOARD ===",
	"Visual feedback showing:",
	"• Currently playing notes (gold)",
	"• Notes in current scale (off-white)",
	"• Notes outside scale (gray)",
	"• Note names on keys",
	"",
	"=== WINDOW CONTROL ===",
	"• Right Click background:",
	"  - Docked: Show undock menu",
	"  - Undocked: Show dock menu",
	"",
	"TIPS:",
	"• Progression slots show beats and repeat info at bottom",
	"• Orange right border indicates loop endpoint",
	"• Green highlight shows selected slot for Alt+Click assignment",
	"• Blue highlight shows currently playing slot",
	"• Hold mode keeps notes playing until KILL is pressed",
}

local windowWidth = 650
local windowHeight = 600
local scrollOffset = 0
local lineHeight = 18
local fontSize = 14

-- Initialize window
gfx.init("ChordGun Help", windowWidth, windowHeight, 0)

function main()
	-- Check if window was resized
	local newWidth = gfx.w
	local newHeight = gfx.h
	
	if newWidth ~= windowWidth or newHeight ~= windowHeight then
		windowWidth = newWidth
		windowHeight = newHeight
		-- Recalculate font size based on height
		fontSize = math.max(10, math.floor(windowHeight / 40))
		gfx.setfont(1, "Arial", fontSize)
		-- Recalculate line height
		lineHeight = math.floor(fontSize * 1.3)
	end
	
	local maxScroll = math.max(0, (#helpLines * lineHeight) - windowHeight + 40)
	
	-- Handle mouse wheel for scrolling
	local mouseWheel = gfx.mouse_wheel
	if mouseWheel ~= 0 then
		scrollOffset = scrollOffset - (mouseWheel * 40)
		scrollOffset = math.max(0, math.min(scrollOffset, maxScroll))
		gfx.mouse_wheel = 0
	end
	
	-- Clear background
	gfx.set(0.15, 0.15, 0.15, 1)
	gfx.rect(0, 0, windowWidth, windowHeight, 1)
	
	-- Draw help text
	gfx.set(0.9, 0.9, 0.9, 1)
	gfx.setfont(1, "Arial", fontSize)
	
	local padding = math.floor(windowWidth * 0.025)
	local yPos = padding - scrollOffset
	for i, line in ipairs(helpLines) do
		if yPos > -lineHeight and yPos < windowHeight then
			gfx.x = padding
			gfx.y = yPos
			gfx.drawstr(line)
		end
		yPos = yPos + lineHeight
	end
	
	-- Draw scrollbar if needed
	if maxScroll > 0 then
		local scrollbarWidth = math.max(10, math.floor(windowWidth * 0.02))
		local scrollbarPadding = math.floor(windowHeight * 0.025)
		local scrollbarHeight = windowHeight - (scrollbarPadding * 2)
		local thumbHeight = math.max(40, scrollbarHeight * (windowHeight / (#helpLines * lineHeight)))
		local thumbPos = scrollbarPadding + (scrollOffset / maxScroll) * (scrollbarHeight - thumbHeight)
		
		-- Scrollbar background
		gfx.set(0.25, 0.25, 0.25, 1)
		gfx.rect(windowWidth - scrollbarWidth - scrollbarPadding, scrollbarPadding, scrollbarWidth, scrollbarHeight, 1)
		
		-- Scrollbar thumb
		gfx.set(0.5, 0.5, 0.5, 1)
		gfx.rect(windowWidth - scrollbarWidth - scrollbarPadding, thumbPos, scrollbarWidth, thumbHeight, 1)
	end
	
	gfx.update()
	
	local char = gfx.getchar()
	if char == 27 or char == -1 then  -- ESC or window closed
		return
	end
	
	reaper.defer(main)
end

main()
