# TK ChordGun - Quick Start Guide

**Enhanced MIDI chord generator with scale filtering, remapping, and real-time chord recognition**

Based on the brilliant [ChordGun by pandabot](https://github.com/benjohnson2001/ChordGun) with powerful performance enhancements.

---

## 🎹 Core Features

### Basic Operation
- **7 Chord Buttons (I-vii°)**: Click to preview, Shift+Click to insert at cursor
- **Scale Selection**: Choose root note and scale type (Major, Minor, Dorian, etc.)
- **Octave Control**: Adjust playback octave (arrows or Alt+,/.)
- **Piano Keyboard**: Visual feedback showing scale notes and what's playing

### Scale Filter/Remap Modes 🆕
Three modes for live MIDI input control:

1. **OFF** - No filtering, all MIDI passes through
2. **FILTER** - Blocks notes outside current scale (perfect for live performance)
3. **REMAP** - Maps white piano keys → scale notes (play scales without wrong notes)

**Setup**: Click **Setup** button to auto-install `TK_Scale_Filter.jsfx` to your track's Input FX chain. Required for Filter/Remap modes to work with MIDI input.

### Chord Recognition 🆕
- Real-time display of chords you're playing (13+ types: maj, min, dim, 7, maj9, etc.)
- **Blue text** = chord root is in current scale
- **Orange text** = chord root outside scale
- Works with chord buttons AND external MIDI keyboard

### 8-Slot Progression System
Build and play chord progressions:
- **Alt+Click** chord button → add to selected slot
- **Click slot** → preview chord
- **Ctrl+Click slot** → edit beats (1/2/4/8) and repeats (1-4)
- **Shift+Click slot** → set loop endpoint
- **Right-Click slot** → clear

**Playback Controls**:
- **PLAY** - Start progression playback
- **STOP** - Stop playback
- **SAVE/LOAD** - Store presets
- **INSERT** - Add entire progression as MIDI notes
- **CLEAR** - Clear all slots

---

## ⌨️ Keyboard Shortcuts

### Preview Notes (lowercase)
```
a s d f g h j   = scale notes (current octave)
z x c v b n m   = scale notes (lower octave)
q w e r t y u   = scale notes (higher octave)
1 2 3 4 5 6 7   = preview chords
```

### Insert Notes (SHIFT + key)
```
A S D F G H J   = insert scale notes (current octave)
Z X C V B N M   = insert scale notes (lower octave)
Q W E R T Y U   = insert scale notes (higher octave)
! @ # $ % ^ &   = insert chords
```

### Other
```
0               = stop all notes
ESC             = close window
Left/Right      = move cursor by grid
Alt + ,/.       = halve/double grid size
Ctrl + ,/.      = change scale root / chord type
```

---

## 🎛️ Pro Tips

1. **Enable Tooltips** - Hover over any button for detailed click/modifier actions
2. **Strum Mode** - Click STRUM button, Ctrl+Click to adjust delay (10-500ms)
3. **Hold Mode** - Toggle HOLD to keep notes playing until KILL is pressed
4. **Filter Mode** - Essential for live performance - prevents wrong notes automatically
5. **Remap Mode** - Great for practice - play any scale using only white keys
6. **Progression Playback** - Set different beats/repeats per slot for dynamic arrangements
7. **Help Window** - Click **?** button for complete reference

---

## 🔧 Setup for Filter/Remap Modes

1. Select a track in REAPER
2. Open TK ChordGun
3. Click **Setup** button (between INSERT and chord display)
4. JSFX will be added to track's Input FX automatically
5. Switch modes with **Off/Filter/Remap** button

**Note**: The JSFX processes MIDI *before* it reaches your instrument, so it must be in Input FX (not Track FX).

---

## 📋 What's New in v1.1.0

- ✅ Scale Filter/Remap modes with JSFX integration
- ✅ Real-time chord recognition (13+ chord types)
- ✅ Setup button for one-click JSFX installation
- ✅ Color-coded chord display (blue/orange)
- ✅ Piano keyboard shows remap arrows (e.g., "E→Eb")
- ✅ Enharmonic spelling adapts to scale context
- ✅ Unified blue color for all playing notes
- ✅ Cross-platform compatible (Windows, macOS, Linux)

---

## 🙏 Credits

Original **ChordGun** by [pandabot](https://github.com/benjohnson2001/ChordGun) - An absolute masterpiece of music theory UX design.

**TK Enhancements** by TouristKiller - Added scale filtering, chord recognition, and workflow improvements while preserving pandabot's brilliant core design.

---

## 📦 Installation

Via **ReaPack**:
1. Add repository: `https://github.com/TouristKiller/TK-Scripts/raw/master/index.xml`
2. Search for "TK ChordGun"
3. Install (includes all helper scripts + JSFX)

Manual:
1. Download `TK_ChordGun` folder
2. Place in `REAPER/Scripts/`
3. Copy `TK_Scale_Filter.jsfx` to `REAPER/Effects/`
4. Load via Actions → Load ReaScript

---

## 🐛 Troubleshooting

**Filter/Remap not working?**
- Ensure JSFX is in **Input FX** (not Track FX)
- Click Setup button to auto-install
- Check that scale mode is set to Filter or Remap

**No chord recognition?**
- Play 3+ notes simultaneously
- Check MIDI input is reaching REAPER
- Works with both chord buttons and external MIDI

**Window always on top?**
- Install [js_ReaScriptAPI extension](https://forum.cockos.com/showthread.php?t=212174) (Windows only)
- See comments at end of script file

---

**Enjoy making music!** 🎵
