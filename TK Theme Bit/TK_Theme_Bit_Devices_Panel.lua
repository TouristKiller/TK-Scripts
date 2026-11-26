-- TK Theme Bit - Devices: Bitwig's device panel for REAPER, meant for the bottom docker. It
-- follows the selected track: the track's strip, then every FX as a device. Run the action
-- again to close it.
--
-- A device: power, presets and the name on its strip (window, remote controls and modulators
-- at the bottom); the plug-in's parameters as a list (search, with the magnifier menu:
-- only automated and modulated ones, modulated ones on top, recent searches) and above it
-- the last touched parameter. Drag a knob (Shift: fine), double-click a modulator knob for
-- its default, right-click for remote controls and modulation.
--
-- Remote controls: pages of 8 knobs per plug-in (Data/TK Theme Bit/remote_controls.json).
-- Learn a slot by moving a parameter in the plug-in's window, or make pages from the plug-in's
-- parameter groups (Auto pages). Double-click a page's name to rename it.
--
-- Modulators: LFO, Steps, Random, Envelope Follower, ADSR, MIDI, Keytrack+, Macro, Macro-4,
-- Button and Buttons, each a small JSFX (written to Effects/TK Theme Bit/) linked through
-- REAPER's parameter modulation. Click a modulator's routing arrow, then a parameter, and
-- drag for the amount; select another track to route there too (global modulation, gmem).
-- Click a tile for its editor. The track strip has the track's own modulators (on the master:
-- the project's).
--
-- What was measured while building it (REAPER 7.86):
--   TrackFX_GetParam returns the modulated value; param.N.mod.baseline is in the
--   parameter's own units; played = norm(baseline) + plink.scale * (source + plink.offset);
--   unlinking leaves no trace. Rapid TrackFX_SetParam with real values on a JSFX log slider
--   crashed REAPER: drags write normalized values.

local r = reaper
if not r.ImGui_CreateContext then
  r.ShowMessageBox("The Devices panel needs ReaImGui (install it through ReaPack).", "TK Theme Bit", 0)
  return
end
do
  local _, _, version = r.ImGui_GetVersion()
  local major, minor = tostring(version):match("^(%d+)%.(%d+)")
  if not major or (tonumber(major) == 0 and tonumber(minor) < 10) then
    r.ShowMessageBox("The Devices panel needs ReaImGui 0.10 or newer.", "TK Theme Bit", 0)
    return
  end
end

if r.set_action_options then r.set_action_options(1 | 4) end
local _, _, section_id, cmd_id = r.get_action_context()

local ctx = r.ImGui_CreateContext("TK Bit Devices")
local font = r.ImGui_CreateFont("Inter")
r.ImGui_Attach(ctx, font)
local font_bold = r.ImGui_CreateFont("Inter", r.ImGui_FontFlags_Bold and r.ImGui_FontFlags_Bold() or 0)
r.ImGui_Attach(ctx, font_bold)

-- the Bit inspector's colours, plus the modulation blue and the knob greys
local C = {
  bg = 0x040404FF, empty = 0x0A0A0AFF, field = 0x040404FF, line = 0x242424FF, accent = 0xFF6000FF,
  text = 0xE6E6E6FF, dim = 0x8A8A8AFF, label = 0xB9B4B4FF, value = 0xF75D07FF,
  headbar = 0x242424FF, headtext = 0xCFCFCFFF, seg_hi = 0x444444FF,
  key_top = 0x363636FF, key_bot = 0x292929FF, key_edge = 0x0A0A0AFF, on_top = 0xFF6000FF, on_bot = 0xF85D00FF,
  card = 0x1B1B1BFF, card_hi = 0x222222FF, card_off = 0x161616FF, hover = 0x262626FF,
  knob = 0x151515FF, track = 0x3C3C3CFF,
  dev = 0x282828FF, dev_strip = 0x282828FF, dev_edge = 0x4A4A4AFF, dev_sel = 0x7C7C7CFF, row_line = 0x141414FF,
  pane = 0x1B1B1BFF, pane_edge = 0x3A3A3AFF, headbox = 0x141414FF,
  env = 0xF0B414FF, env_text = 0x1A1A1AFF, grid = 0x242424FF, meter = 0x8A3A12FF,
  kt = 0xE0262EFF, kt_fill = 0x8A101866, canvas = 0x0E0E0EFF,
  k_body = 0x3A3A3AFF, k_body_hi = 0x464646FF, k_edge = 0x141414FF, k_track = 0x2A2A2AFF, box = 0x2E2E2EFF,
  pane_head = 0x242424FF, tile_on = 0x2A2A2AFF,
  icon = 0x9A9A9AFF, mod = 0x5FB8FFFF, mod_dim = 0x5FB8FF55, good = 0x7BD36AFF, bad = 0xFF5A4AFF,
}
local STRIP, ROW, SLOT, GAP, SH = 22, 31, 52, 14, 56
local GS = "TK Bit Global"                  -- global modulation: the project's slot table (ProjExtState)
local SHAPES = { "Sine", "Triangle", "Saw", "Square", "Random" }
local LFO_SRC = [[
desc:TK Bit LFO
//tags: modulation
// Written by TK_Theme_Bit_Devices_Panel.lua (TK Theme Bit). A modulator for REAPER's parameter
// linking: Output (0..1) is the source; the panel links it to a parameter with param.N.plink.*.
// Audio passes through untouched.
slider1:out=0.5<0,1,0.0001>Output
slider2:rate=1<0.02,20,0.01:log>Rate (Hz)
slider3:shape=0<0,4,1{Sine,Triangle,Saw,Square,Random}>Shape
slider4:phase0=0<0,1,0.01>Phase
slider5:amount=1<0,1,0.01>Amount
slider6:bipolar=1<0,1,1{Off,On}>Bipolar
slider7:sync=0<0,1,1{Free,Sync}>Mode
slider8:tbase=4<0,7,1{4/1,2/1,1/1,1/2,1/4,1/8,1/16,1/32}>Timebase
slider9:curve=0<-1,1,0.01>Curve
options:no_meter

@init
ph = 0;
held = rand(1);

@block
lastph = ph;
beats = 16 / (2 ^ tbase);        // 4/1 = 16 beats ... 1/32 = 0.125
sync >= 0.5 ? (
  // tempo sync: locked to the song position while playing, at the tempo while stopped
  (play_state & 1) ? ( ph = beat_position / beats; ) : ( ph += tempo / 60 / beats * samplesblock / srate; );
) : (
  ph += rate * samplesblock / srate;
);
ph -= floor(ph);
ph < lastph ? ( held = rand(1); );
p = ph + phase0;
p -= floor(p);
shape == 0 ? ( v = 0.5 + 0.5 * sin(2 * $pi * p); ) :
shape == 1 ? ( v = p < 0.5 ? 2 * p : 2 - 2 * p; ) :
shape == 2 ? ( v = p; ) :
shape == 3 ? ( v = p < 0.5 ? 1 : 0; ) :
( v = held; );
// curve bends the shape: > 0 holds it low longer, < 0 high
curve > 0.001 ? ( v = v ^ (1 + 3 * curve); );
curve < -0.001 ? ( v = 1 - (1 - v) ^ (1 - 3 * curve); );
// bipolar: around 0.5 (the routes' offset is -0.5); unipolar: up from 0 (offset 0)
out = bipolar >= 0.5 ? 0.5 + (v - 0.5) * amount : v * amount;
sliderchange(1);
]]

-- the other modulators: the same build as the LFO (Output = slider1 = the plink source, Amount,
-- Bipolar), each its own JSFX in Effects/TK Theme Bit/
local STEPS_SRC = [[
desc:TK Bit Steps
//tags: modulation
// Written by TK_Theme_Bit_Devices_Panel.lua (TK Theme Bit): a step sequencer for REAPER's
// parameter linking, locked to the song position while playing. Audio passes through.
slider1:out=0.5<0,1,0.0001>Output
slider2:nsteps=8<1,16,1>Steps
slider3:tbase=5<0,7,1{4/1,2/1,1/1,1/2,1/4,1/8,1/16,1/32}>Timebase
slider4:smooth=0<0,1,0.01>Smooth
slider5:amount=1<0,1,0.01>Amount
slider6:bipolar=1<0,1,1{Off,On}>Bipolar
slider7:pos=0<0,15,1>-Position
slider10:st1=0.75<0,1,0.01>-Step 1
slider11:st2=0.25<0,1,0.01>-Step 2
slider12:st3=0.5<0,1,0.01>-Step 3
slider13:st4=1<0,1,0.01>-Step 4
slider14:st5=0.25<0,1,0.01>-Step 5
slider15:st6=0.6<0,1,0.01>-Step 6
slider16:st7=0.9<0,1,0.01>-Step 7
slider17:st8=0.4<0,1,0.01>-Step 8
slider18:st9=0.8<0,1,0.01>-Step 9
slider19:st10=0.3<0,1,0.01>-Step 10
slider20:st11=0.55<0,1,0.01>-Step 11
slider21:st12=0.95<0,1,0.01>-Step 12
slider22:st13=0.2<0,1,0.01>-Step 13
slider23:st14=0.65<0,1,0.01>-Step 14
slider24:st15=0.45<0,1,0.01>-Step 15
slider25:st16=0.85<0,1,0.01>-Step 16
options:no_meter

@init
ph = 0;
cur = slider(10);

@block
beats = 16 / (2 ^ tbase);
(play_state & 1) ? ( ph = beat_position / beats; ) : ( ph += tempo / 60 / beats * samplesblock / srate; );
n = max(1, floor(nsteps + 0.5));
ph > 100000 ? ( ph -= n * floor(ph / n); );
pos = floor(ph) % n;
target = slider(10 + pos);
k = smooth > 0.001 ? min(1, samplesblock / srate / (smooth * 0.2)) : 1;
cur += (target - cur) * k;
out = bipolar >= 0.5 ? 0.5 + (cur - 0.5) * amount : cur * amount;
sliderchange(1 + 64);
]]

local RANDOM_SRC = [[
desc:TK Bit Random
//tags: modulation
// Written by TK_Theme_Bit_Devices_Panel.lua (TK Theme Bit): random values for REAPER's
// parameter linking, held (Smooth 0) or gliding. Audio passes through.
slider1:out=0.5<0,1,0.0001>Output
slider2:rate=2<0.02,20,0.01:log>Rate (Hz)
slider3:sync=0<0,1,1{Free,Sync}>Mode
slider4:tbase=5<0,7,1{4/1,2/1,1/1,1/2,1/4,1/8,1/16,1/32}>Timebase
slider5:smooth=0.5<0,1,0.01>Smooth
slider6:amount=1<0,1,0.01>Amount
slider7:bipolar=1<0,1,1{Off,On}>Bipolar
options:no_meter

@init
ph = 0;
held = rand(1);
v = held;
prev = held;

@block
lastph = ph;
beats = 16 / (2 ^ tbase);
sync >= 0.5 ? (
  (play_state & 1) ? ( ph = beat_position / beats; ) : ( ph += tempo / 60 / beats * samplesblock / srate; );
) : (
  ph += rate * samplesblock / srate;
);
ph -= floor(ph);
ph < lastph ? ( prev = v; held = rand(1); );
smooth > 0.001 ? (
  t = min(1, ph / smooth);
  t = 0.5 - 0.5 * cos($pi * t);
  v = prev + (held - prev) * t;
) : (
  v = held;
);
out = bipolar >= 0.5 ? 0.5 + (v - 0.5) * amount : v * amount;
sliderchange(1);
]]

local FOLLOWER_SRC = [[
desc:TK Bit Follower
//tags: modulation
// Written by TK_Theme_Bit_Devices_Panel.lua (TK Theme Bit): an envelope follower for REAPER's
// parameter linking: the level of the track (or sidechain 3/4), -60..0 dB = 0..1.
slider1:out=0<0,1,0.0001>Output
slider2:att=10<0.1,500,0.1:log>Rise (ms)
slider3:rel=200<1,3000,1:log>Fall (ms)
slider4:gain=0<-24,24,0.1>Gain (dB)
slider5:input=0<0,1,1{Main,Sidechain 3/4}>Input
slider6:amount=1<0,1,0.01>Amount
slider7:bipolar=0<0,1,1{Off,On}>Bipolar
slider8:lvl=-120<-120,12,0.1>-Level (dB)
in_pin:left
in_pin:right
in_pin:sidechain left
in_pin:sidechain right
out_pin:left
out_pin:right
options:no_meter

@init
env = 0;

@slider
ga = exp(-1 / max(1, att * 0.001 * srate));
gr = exp(-1 / max(1, rel * 0.001 * srate));
g = 10 ^ (gain / 20);

@sample
x = input >= 0.5 ? max(abs(spl2), abs(spl3)) : max(abs(spl0), abs(spl1));
x *= g;
env = x > env ? ga * env + (1 - ga) * x : gr * env + (1 - gr) * x;

@block
db = env > 0.000001 ? 20 * log10(env) : -120;
v = min(1, max(0, (db + 60) / 60));
out = bipolar >= 0.5 ? 0.5 + (v - 0.5) * amount : v * amount;
lvl = max(-120, db);                // what it hears, for the panel's input meter
sliderchange(1 + 128);
]]

local MACRO_SRC = [[
desc:TK Bit Macro
//tags: modulation
// Written by TK_Theme_Bit_Devices_Panel.lua (TK Theme Bit): one knob (Value, automatable) for
// REAPER's parameter linking. Audio passes through.
slider1:out=0<0,1,0.0001>Output
slider2:value=0<0,1,0.001>Value
slider3:amount=1<0,1,0.01>Amount
slider4:bipolar=0<0,1,1{Off,On}>Bipolar
options:no_meter

@slider
out = bipolar >= 0.5 ? 0.5 + (value - 0.5) * amount : value * amount;

@block
out = bipolar >= 0.5 ? 0.5 + (value - 0.5) * amount : value * amount;
sliderchange(1);
]]

-- five more (2026-11-26): ADSR, MIDI and Keytrack read the MIDI notes, so they sit at the START
-- of the chain (an instrument does not pass its MIDI on) and send the MIDI on unchanged
local ADSR_SRC = [[
desc:TK Bit ADSR
//tags: modulation
// Written by TK_Theme_Bit_Devices_Panel.lua (TK Theme Bit): an ADSR envelope for REAPER's
// parameter linking, played by the MIDI notes. It passes the MIDI and the audio on.
slider1:out=0<0,1,0.0001>Output
slider2:att=10<0.5,5000,0.1:log>Attack (ms)
slider3:dec=300<1,5000,1:log>Decay (ms)
slider4:sus=0.6<0,1,0.01>Sustain
slider5:rel=400<1,10000,1:log>Release (ms)
slider6:vel=0.5<0,1,0.01>Velocity
slider7:single=0<0,1,1{Off,On}>Single
slider8:amount=1<0,1,0.01>Amount
slider9:bipolar=0<0,1,1{Off,On}>Bipolar
options:no_meter

@init
env = 0;
stage = 0;
held = 0;
velv = 1;
relrate = 0;

@block
while (midirecv(ofs, m1, m2, m3)) (
  st = m1 & 0xF0;
  st == 0x90 && m3 > 0 ? (
    held += 1;
    (single < 0.5 || held == 1) ? ( stage = 1; velv = m3 / 127; );
  ) : (st == 0x80 || (st == 0x90 && m3 == 0) || (st == 0xB0 && m2 == 123)) ? (
    held = (st == 0xB0) ? 0 : max(0, held - 1);
    held == 0 ? ( stage = 4; relrate = env / max(0.001, rel * 0.001); );
  );
  midisend(ofs, m1, m2, m3);
);
dt = samplesblock / srate;
stage == 1 ? ( env += dt / max(0.0005, att * 0.001); env >= 1 ? ( env = 1; stage = 2; ); );
stage == 2 ? ( env -= dt / max(0.001, dec * 0.001) * (1 - sus); env <= sus ? ( env = sus; stage = 3; ); );
stage == 3 ? ( env = sus; );
stage == 4 ? ( env -= relrate * dt; env <= 0 ? ( env = 0; stage = 0; ); );
v = env * (1 - vel * (1 - velv));
out = bipolar >= 0.5 ? 0.5 + (v - 0.5) * amount : v * amount;
sliderchange(1);
]]

local MIDI_SRC = [[
desc:TK Bit MIDI
//tags: modulation
// Written by TK_Theme_Bit_Devices_Panel.lua (TK Theme Bit): a CC, pitch bend, aftertouch or
// velocity as a source for REAPER's parameter linking. It passes the MIDI and the audio on.
slider1:out=0<0,1,0.0001>Output
slider2:type=0<0,3,1{CC,Pitch Bend,Aftertouch,Velocity}>Type
slider3:ccn=1<0,127,1>CC
slider4:chan=0<0,16,1{Omni,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16}>Channel
slider5:smooth=0.1<0,1,0.01>Smooth
slider6:amount=1<0,1,0.01>Amount
slider7:bipolar=0<0,1,1{Off,On}>Bipolar
slider8:learn=0<0,1,1{Off,On}>-Learn
options:no_meter

@init
val = type == 1 ? 0.5 : 0;
cur = val;

@block
while (midirecv(ofs, m1, m2, m3)) (
  st = m1 & 0xF0;
  ch = (m1 & 0x0F) + 1;
  // Learn CC: the next CC that comes in becomes the controller
  (learn >= 0.5 && st == 0xB0) ? ( ccn = m2; type = 0; learn = 0; sliderchange(2 + 4 + 128); );
  (chan < 0.5 || ch == chan) ? (
    type == 0 ? ( (st == 0xB0 && m2 == ccn) ? ( val = m3 / 127; ); ) :
    type == 1 ? ( st == 0xE0 ? ( val = (m3 * 128 + m2) / 16383; ); ) :
    type == 2 ? ( st == 0xD0 ? ( val = m2 / 127; ); st == 0xA0 ? ( val = m3 / 127; ); ) :
    ( (st == 0x90 && m3 > 0) ? ( val = m3 / 127; ); );
  );
  midisend(ofs, m1, m2, m3);
);
k = smooth > 0.001 ? min(1, samplesblock / srate / (smooth * 0.3)) : 1;
cur += (val - cur) * k;
out = bipolar >= 0.5 ? 0.5 + (cur - 0.5) * amount : cur * amount;
sliderchange(1);
]]

local KEYTRACK_SRC = [[
desc:TK Bit Keytrack
//tags: modulation
// Written by TK_Theme_Bit_Devices_Panel.lua (TK Theme Bit): the note played (Low note = 0 ..
// High note = 1) as a source for REAPER's parameter linking. Passes the MIDI and audio on.
slider1:out=0<0,1,0.0001>Output
slider2:lo=36<0,127,1>Low note
slider3:hi=96<0,127,1>High note
slider4:glide=0<0,1,0.01>Glide
slider5:amount=1<0,1,0.01>Amount
slider6:bipolar=0<0,1,1{Off,On}>Bipolar
slider7:npts=2<2,8,1>-Points
slider8:kpos=0<0,1,0.001>-Key
slider10:x1=0<0,1,0.001>-P1 x
slider11:y1=0<0,1,0.001>-P1 y
slider12:x2=1<0,1,0.001>-P2 x
slider13:y2=1<0,1,0.001>-P2 y
slider14:x3=0<0,1,0.001>-P3 x
slider15:y3=0<0,1,0.001>-P3 y
slider16:x4=0<0,1,0.001>-P4 x
slider17:y4=0<0,1,0.001>-P4 y
slider18:x5=0<0,1,0.001>-P5 x
slider19:y5=0<0,1,0.001>-P5 y
slider20:x6=0<0,1,0.001>-P6 x
slider21:y6=0<0,1,0.001>-P6 y
slider22:x7=0<0,1,0.001>-P7 x
slider23:y7=0<0,1,0.001>-P7 y
slider24:x8=0<0,1,0.001>-P8 x
slider25:y8=0<0,1,0.001>-P8 y
options:no_meter

@init
note = 60;
cur = 0;

@block
while (midirecv(ofs, m1, m2, m3)) (
  st = m1 & 0xF0;
  (st == 0x90 && m3 > 0) ? ( note = m2; );
  midisend(ofs, m1, m2, m3);
);
t = hi != lo ? (note - lo) / (hi - lo) : 0;
t = min(1, max(0, t));
// the curve: points P1..Pn (x sorted, 0..1), straight between them
n = max(2, min(8, floor(npts + 0.5)));
target = slider(11);
t > slider(10) ? (
  i = 0;
  loop(n - 1,
    xa = slider(10 + 2 * i); ya = slider(11 + 2 * i);
    xb = slider(12 + 2 * i); yb = slider(13 + 2 * i);
    (t >= xa && t <= xb) ? ( target = xb > xa ? ya + (yb - ya) * (t - xa) / (xb - xa) : yb; );
    i += 1;
  );
  t > slider(10 + 2 * (n - 1)) ? ( target = slider(11 + 2 * (n - 1)); );
);
kpos = t;
k = glide > 0.001 ? min(1, samplesblock / srate / (glide * 0.5)) : 1;
cur += (target - cur) * k;
out = bipolar >= 0.5 ? 0.5 + (cur - 0.5) * amount : cur * amount;
sliderchange(1 + 128);
]]

local MACRO4_SRC = [[
desc:TK Bit Macro-4
//tags: modulation
// Written by TK_Theme_Bit_Devices_Panel.lua (TK Theme Bit): four knobs, each its own source
// for REAPER's parameter linking (automatable). Audio passes through.
slider1:mc1=0<0,1,0.001>Macro 1
slider2:mc2=0<0,1,0.001>Macro 2
slider3:mc3=0<0,1,0.001>Macro 3
slider4:mc4=0<0,1,0.001>Macro 4
slider5:bipolar=0<0,1,1{Off,On}>Bipolar
options:no_meter

@block
]]

local BUTTON_SRC = [[
desc:TK Bit Button
//tags: modulation
// Written by TK_Theme_Bit_Devices_Panel.lua (TK Theme Bit): an on/off button (toggle or
// momentary, with a glide) as a source for REAPER's parameter linking. Audio passes through.
slider1:out=0<0,1,0.0001>Output
slider2:btn=0<0,1,1{Off,On}>Button
slider3:mode=0<0,1,1{Toggle,Momentary}>Mode
slider4:smooth=0<0,1,0.01>Smooth
slider5:amount=1<0,1,0.01>Amount
slider6:bipolar=0<0,1,1{Off,On}>Bipolar
options:no_meter

@init
cur = 0;

@block
k = smooth > 0.001 ? min(1, samplesblock / srate / (smooth * 0.5)) : 1;
cur += ((btn >= 0.5 ? 1 : 0) - cur) * k;
out = bipolar >= 0.5 ? 0.5 + (cur - 0.5) * amount : cur * amount;
sliderchange(1);
]]

local BUTTONS_SRC = [[
desc:TK Bit Buttons
//tags: modulation
// Written by TK_Theme_Bit_Devices_Panel.lua (TK Theme Bit): two on/off buttons, A and B, each
// its own source for REAPER's parameter linking. Audio passes through.
slider1:ba=0<0,1,1{Off,On}>A
slider2:bb=0<0,1,1{Off,On}>B
slider3:mode=0<0,1,1{Toggle,Momentary}>Mode
slider4:bipolar=0<0,1,1{Off,On}>Bipolar
options:no_meter

@block
]]

-- global modulation (gmem): a Send on the source's track takes the modulator's output (plink,
-- base 0, scale 1) and writes it to slot n of gmem "TKBitGlobal"; a Global on another track
-- reads slot n as its Output, the source of an ordinary plink there. Both are hidden in the row.
local GSEND_SRC = [[
desc:TK Bit Global Send
//tags: modulation
// Written by TK_Theme_Bit_Devices_Panel.lua (TK Theme Bit): writes In (linked from a modulator)
// to gmem slot Slot, for TK Bit Global on other tracks. Audio passes through.
slider1:inp=0<0,1,0.0001>In
slider2:slot=1<1,64,1>Slot
options:no_meter gmem=TKBitGlobal

@block
gmem[slot] = inp;
]]

local GRECV_SRC = [[
desc:TK Bit Global
//tags: modulation
// Written by TK_Theme_Bit_Devices_Panel.lua (TK Theme Bit): reads gmem slot Slot (a modulator
// on another track, through TK Bit Global Send) as Output for REAPER's parameter linking.
slider1:out=0<0,1,0.0001>Output
slider2:slot=1<1,64,1>Slot
slider3:bipolar=0<0,1,1{Off,On}>Bipolar
options:no_meter gmem=TKBitGlobal

@block
out = gmem[slot];
sliderchange(1);
]]

-- the modulators: what the "+" offers, how they are found back in the chain (desc)
local MODS = {
  order = { "lfo", "steps", "random", "follower", "adsr", "midi", "keytrack", "macro", "macro4", "button", "buttons" },
  lfo = { label = "LFO", menu = "LFO", desc = "TK Bit LFO", file = "TK Bit LFO.jsfx", src = LFO_SRC },
  steps = { label = "Steps", menu = "Steps", desc = "TK Bit Steps", file = "TK Bit Steps.jsfx", src = STEPS_SRC },
  random = { label = "Random", menu = "Random", desc = "TK Bit Random", file = "TK Bit Random.jsfx", src = RANDOM_SRC },
  follower = { label = "Follower", menu = "Envelope Follower", desc = "TK Bit Follower", file = "TK Bit Follower.jsfx", src = FOLLOWER_SRC },
  macro = { label = "Macro", menu = "Macro", desc = "TK Bit Macro", file = "TK Bit Macro.jsfx", src = MACRO_SRC },
  adsr = { label = "ADSR", menu = "ADSR", desc = "TK Bit ADSR", file = "TK Bit ADSR.jsfx", src = ADSR_SRC, first = true },
  midi = { label = "MIDI", menu = "MIDI", desc = "TK Bit MIDI", file = "TK Bit MIDI.jsfx", src = MIDI_SRC, first = true },
  keytrack = { label = "Keytrack+", menu = "Keytrack+", desc = "TK Bit Keytrack", file = "TK Bit Keytrack.jsfx",
    src = KEYTRACK_SRC, first = true },
  macro4 = { label = "Macro-4", menu = "Macro-4", desc = "TK Bit Macro-4", file = "TK Bit Macro-4.jsfx", src = MACRO4_SRC },
  button = { label = "Button", menu = "Button", desc = "TK Bit Button", file = "TK Bit Button.jsfx", src = BUTTON_SRC },
  buttons = { label = "Buttons", menu = "Buttons", desc = "TK Bit Buttons", file = "TK Bit Buttons.jsfx", src = BUTTONS_SRC },
  gsend = { label = "Global Send", menu = "Global Send", desc = "TK Bit Global Send", file = "TK Bit Global Send.jsfx", src = GSEND_SRC },
  grecv = { label = "Global", menu = "Global", desc = "TK Bit Global", file = "TK Bit Global.jsfx", src = GRECV_SRC },
}


local S = {
  guid = nil,              -- the selected card (FX GUID)
  track = nil, search = "", stress = false,
  dock_to = nil, close = false,
  names = {},              -- per FX GUID: { n = count, list = { {p, name, lower} } }
  filt = {},               -- the filtered list, with its key
  mods = {},               -- per FX GUID: { [param] = true } for modulated parameters
  scan_count = -1, scan_t = 0,
  menu_p = nil, drag = nil,
  txtc = {},               -- per FX GUID: { [param] = { value, text } }
  log = {},
  learn = nil,             -- { guid, page, slot, snap }: a remote slot waiting for a touched parameter
  rckey = {},              -- per FX GUID: the plugin's original name (the key in the remote file)
  rcpage = {},             -- per FX GUID: the page on show
  rcmod = {},              -- per FX GUID: the modulator (LFO GUID) whose page is on show
  rcres = {},              -- "guid|name" -> parameter index (or false), when the stored index moved
  rcmenu = nil,            -- the slot or page menu: { guid, page, slot, open }
  show_list = r.GetExtState("TK Bit Devices", "show_list") ~= "0",
  q = {},                  -- per FX GUID: the device's search text
  vr = {}, vl = {},        -- per FX GUID: remote controls pane shown, parameter list shown
  joker = {},              -- per FX GUID: the last touched parameter (Bitwig's knob above the list)
  touch_snap = "",         -- GetTouchedOrFocusedFX as last seen
  fmod = {},               -- per FX GUID: list shows only automated and modulated parameters
  auto = {},               -- per FX GUID: { [param] = true } for parameters with an envelope
  hist = {},               -- recent searches, newest first
  vm = {},                 -- per FX GUID: the modulators pane shown
  mexp = {},               -- per FX GUID: the modulator (GUID) whose editor is unfolded (">")
  hidden = {},             -- FX GUIDs the row does not show (Global Send / Global)
  pinmod = r.GetExtState("TK Bit Devices", "pin_mod") ~= "0",   -- modulated parameters on top of the list
  route_src = nil,         -- the modulator being routed: { track, lg, out, label } (across tracks)
  route = nil,             -- the LFO (GUID) whose routing button is on
  routes = {},             -- per LFO GUID: { { tgt = FX GUID, p = param } }
  lfo_owner = {},          -- per LFO GUID: the device it belongs to (it is hidden from the row)
  owned = {},              -- per device GUID: its LFOs, in chain order
}

local H, U, F, M, D = {}, {}, {}, {}, {}

---------------------------------------------------------------- helpers
function H.clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function H.mods()
  local m = r.ImGui_GetKeyMods(ctx)
  return (m & r.ImGui_Mod_Shift()) ~= 0, (m & r.ImGui_Mod_Ctrl()) ~= 0, (m & r.ImGui_Mod_Alt()) ~= 0
end
-- notes for whoever looks (no console: it would pop REAPER's console window up)
function H.say(s)
  S.log[#S.log + 1] = s
  if #S.log > 200 then table.remove(S.log, 1) end
end
-- text cut to fit w pixels, with a dot. Cached: cutting a long name asks CalcTextSize once
-- per letter, which made the first proof cost ~115 us per knob (2026-11-25 report).
H.fitc, H.fitn = {}, 0
function H.fit(s, w)
  local key = w .. "|" .. s
  local hit = H.fitc[key]
  if hit then return hit end
  local out = ""
  if (r.ImGui_CalcTextSize(ctx, s)) <= w then
    out = s
  else
    for n = #s - 1, 1, -1 do
      local c = s:sub(1, n) .. "."
      if (r.ImGui_CalcTextSize(ctx, c)) <= w then out = c; break end
    end
  end
  if H.fitn > 4000 then H.fitc, H.fitn = {}, 0 end
  H.fitc[key], H.fitn = out, H.fitn + 1
  return out
end
-- deleting an FX mid-frame leaves the rest of the frame drawing an index that is gone
-- ("table index is nil" on LFO delete, 2026-11-25): such actions run after the frame
H.queue = {}
function H.later(fn) H.queue[#H.queue + 1] = fn end
function H.run_later()
  local q = H.queue
  H.queue = {}
  for _, fn in ipairs(q) do fn() end
end

---------------------------------------------------------------- FX
function F.track()
  local tr = r.GetSelectedTrack(0, 0)
  return tr
end
function F.index(tr, guid)
  if not guid then return nil end
  for i = 0, r.TrackFX_GetCount(tr) - 1 do
    if r.TrackFX_GetFXGUID(tr, i) == guid then return i end
  end
end
-- "VST3: Pro-Q 3 (FabFilter)" -> "Pro-Q 3"
S.namec, S.lfoc = {}, {}
function F.name(tr, i)
  local g = r.TrackFX_GetFXGUID(tr, i)
  if not g then return "" end
  local hit = S.namec[g]
  if hit then return hit end
  local _, n = r.TrackFX_GetFXName(tr, i, "")
  n = n:gsub("^%w+i?:%s*", ""):gsub("%s*%([^%(%)]*%)%s*$", "")
  S.namec[g] = n
  return n
end
-- which of our modulators FX i is ("lfo", "steps", ...), or nil
function F.mod_kind(tr, i)
  local g = r.TrackFX_GetFXGUID(tr, i)
  if not g then return nil end
  local c = S.lfoc[g]
  if c ~= nil then return c or nil end
  local _, n = r.TrackFX_GetFXName(tr, i, "")
  local ok, id = r.TrackFX_GetNamedConfigParm(tr, i, "fx_ident")
  local kind = false
  for _, k in ipairs(MODS.all) do
    local d = MODS[k].desc
    if n:sub(-#d) == d or (ok and id:find("/" .. MODS[k].file, 1, true)) or (ok and id:find("\\" .. MODS[k].file, 1, true))
      or (ok and id == MODS[k].file) then kind = k; break end
  end
  S.lfoc[g] = kind
  return kind or nil
end
function F.is_lfo(tr, i) return F.mod_kind(tr, i) ~= nil end      -- any of our modulators
function F.cfg(tr, i, p, key)
  local ok, v = r.TrackFX_GetNamedConfigParm(tr, i, "param." .. p .. "." .. key)
  return ok and tonumber(v) or nil
end
function F.set(tr, i, p, key, v)
  return r.TrackFX_SetNamedConfigParm(tr, i, "param." .. p .. "." .. key, tostring(v))
end
-- mod.baseline is in the parameter's own units (TrackFX_GetParam's min..max), not 0..1:
-- the second proof run (2026-11-25) on a JSFX "(%)" slider showed REAPER using ~0.009
-- where 0.931 was written as if normalized. These two convert, with the range cached.
S.rng = {}
function F.range(tr, i, p)
  local key = r.TrackFX_GetFXGUID(tr, i) .. p
  local c = S.rng[key]
  if not c then
    local _, mn, mx = r.TrackFX_GetParam(tr, i, p)
    c = { mn, mx > mn and mx or mn + 1 }
    S.rng[key] = c
  end
  return c[1], c[2]
end
function F.base_get(tr, i, p)
  local b = F.cfg(tr, i, p, "mod.baseline")
  if not b then return nil end
  local mn, mx = F.range(tr, i, p)
  return H.clamp((b - mn) / (mx - mn), 0, 1)
end
function F.base_set(tr, i, p, t)
  local mn, mx = F.range(tr, i, p)
  return F.set(tr, i, p, "mod.baseline", mn + t * (mx - mn))
end
-- the parameter names, asked once per FX (and again when the count changes)
function F.params(tr, i, guid)
  local n = r.TrackFX_GetNumParams(tr, i)
  local c = S.names[guid]
  if c and c.n == n then return c end
  c = { n = n, list = {} }
  for p = 0, n - 1 do
    local _, name = r.TrackFX_GetParamName(tr, i, p, "")
    c.list[#c.list + 1] = { p, name, name:lower() }
  end
  S.names[guid] = c
  return c
end
S.pidx = {}
function F.param_index_c(tr, i, want)
  local key = r.TrackFX_GetFXGUID(tr, i) .. want
  local hit = S.pidx[key]
  if hit == nil then hit = F.param_index(tr, i, want) or false; S.pidx[key] = hit end
  return hit or nil
end
function F.param_index(tr, i, want)
  for p = 0, r.TrackFX_GetNumParams(tr, i) - 1 do
    local _, name = r.TrackFX_GetParamName(tr, i, p, "")
    if name == want then return p end
  end
end
-- which parameters are modulated, and the LFO link if there is one: on a track change, and
-- (at most once a second) when the project changed, not while a knob is held
function F.scan(tr, force)
  local cnt = r.GetProjectStateChangeCount(0)
  local now = r.time_precise()
  if not force and (cnt == S.scan_count or now - S.scan_t < 1 or S.drag) then return end
  S.scan_count, S.scan_t = cnt, now
  S.mods, S.namec, S.lfoc, S.pidx = {}, {}, {}, {}
  S.routes, S.lfo_owner, S.owned, S.hidden = {}, {}, {}, {}
  for i = 0, r.TrackFX_GetCount(tr) - 1 do
    local guid = r.TrackFX_GetFXGUID(tr, i)
    local set, aut = {}, {}
    for p = 0, r.TrackFX_GetNumParams(tr, i) - 1 do
      if r.GetFXEnvelope(tr, i, p, false) then aut[p] = true end
      if (F.cfg(tr, i, p, "mod.active") or 0) ~= 0 then
        set[p] = true
        if (F.cfg(tr, i, p, "plink.active") or 0) ~= 0 then
          local src = F.cfg(tr, i, p, "plink.effect") or -1
          if src >= 0 and src < r.TrackFX_GetCount(tr) and F.is_lfo(tr, src) then
            local lg = r.TrackFX_GetFXGUID(tr, src)
            S.routes[lg] = S.routes[lg] or {}
            table.insert(S.routes[lg], { tgt = guid, p = p })
          end
        end
      end
    end
    S.mods[guid] = set
    S.auto[guid] = aut
  end
  -- every LFO belongs to a device: the one stored in the track, else its first target's
  for i = 0, r.TrackFX_GetCount(tr) - 1 do
    local mk = F.mod_kind(tr, i)
    if mk == "gsend" or mk == "grecv" then
      S.hidden[r.TrackFX_GetFXGUID(tr, i)] = true
    elseif mk then
      local lg = r.TrackFX_GetFXGUID(tr, i)
      local _, owner = r.GetSetMediaTrackInfo_String(tr, M.key(lg), "", false)
      if owner ~= "TRACK" and (owner == "" or not F.index(tr, owner)) then
        owner = S.routes[lg] and S.routes[lg][1].tgt or nil
      end
      if owner and owner ~= lg then
        S.lfo_owner[lg] = owner
        S.owned[owner] = S.owned[owner] or {}
        table.insert(S.owned[owner], lg)
      end
    end
  end
end

---------------------------------------------------------------- modulation
-- the JSFX goes into Effects/TK Theme Bit/, written again only when its text differs
function M.install(kind)
  local m = MODS[kind or "lfo"]
  local dir = r.GetResourcePath() .. "/Effects/TK Theme Bit"
  local path = dir .. "/" .. m.file
  local f = io.open(path, "rb")
  local cur = f and f:read("*a")
  if f then f:close() end
  if cur == m.src then return true end
  r.RecursiveCreateDirectory(dir, 0)
  f = io.open(path, "wb")
  if not f then return false end
  f:write(m.src)
  f:close()
  H.say("wrote " .. path)
  return true
end

S.out_cache = {}
function F.param_index_cached(tr, li)
  local g = r.TrackFX_GetFXGUID(tr, li)
  local c = S.out_cache[g]
  if not c then c = F.param_index(tr, li, "Output") or 0; S.out_cache[g] = c end
  return c
end

---------------------------------------------------------------- widgets (the inspector's)
function U.text_col(col, s)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), col)
  r.ImGui_Text(ctx, s)
  r.ImGui_PopStyleColor(ctx)
end

-- the header bar with the dock and close icons at its right end
function U.head(title)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local w = r.ImGui_GetContentRegionAvail(ctx)
  r.ImGui_DrawList_AddRectFilled(dl, x - 6, y, x + w + 6, y + 20, C.headbar)
  r.ImGui_PushFont(ctx, font_bold, 11)
  local tw, th = r.ImGui_CalcTextSize(ctx, title)
  r.ImGui_DrawList_AddText(dl, x + math.max(0, (w - 40 - tw) / 2), y + (20 - th) / 2, C.headtext, title)
  r.ImGui_PopFont(ctx)
  local docked = r.ImGui_IsWindowDocked(ctx)
  r.ImGui_SetCursorScreenPos(ctx, x + w - 38, y + 2)
  if r.ImGui_InvisibleButton(ctx, "##dock", 16, 16) then S.dock_to = docked and 0 or -1 end
  local hov = r.ImGui_IsItemHovered(ctx)
  local ic = hov and C.text or C.dim
  r.ImGui_DrawList_AddRect(dl, x + w - 35, y + 5, x + w - 25, y + 14, ic, 1)
  if docked then r.ImGui_DrawList_AddRectFilled(dl, x + w - 35, y + 11, x + w - 25, y + 14, C.accent) end
  if hov then
    r.ImGui_SetTooltip(ctx, docked and "Float the panel"
      or "Dock the panel (in REAPER's first docker; set that docker to the bottom for Bitwig's place)")
  end
  r.ImGui_SetCursorScreenPos(ctx, x + w - 19, y + 2)
  if r.ImGui_InvisibleButton(ctx, "##close", 16, 16) then S.close = true end
  hov = r.ImGui_IsItemHovered(ctx)
  ic = hov and C.text or C.dim
  r.ImGui_DrawList_AddLine(dl, x + w - 15, y + 6, x + w - 8, y + 13, ic, 1.4)
  r.ImGui_DrawList_AddLine(dl, x + w - 8, y + 6, x + w - 15, y + 13, ic, 1.4)
  if hov then r.ImGui_SetTooltip(ctx, "Close the panel") end
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  r.ImGui_Dummy(ctx, w, 22)
end

-- a key as Bitwig draws them: grey, orange when on
function U.key(id, text, on, w, h, tip)
  w, h = math.max(1, math.floor(w)), math.max(1, math.floor(h))   -- ImGui asserts on a 0 size
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local hit = r.ImGui_InvisibleButton(ctx, "##k" .. id, w, h)
  local hov, act = r.ImGui_IsItemHovered(ctx), r.ImGui_IsItemActive(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local top, bot = C.key_top, C.key_bot
  if on then top, bot = C.on_top, C.on_bot end
  if hov and not on then top, bot = C.seg_hi, 0x333333FF end
  if act then top, bot = bot, top end
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, C.key_edge, 3)
  r.ImGui_DrawList_AddRectFilledMultiColor(dl, x + 1, y + 1, x + w - 1, y + h - 1, top, top, bot, bot)
  local ink = on and 0x141414FF or C.text
  if type(text) == "function" then
    text(dl, x + w / 2, y + h / 2, ink)
  else
    local tw, th = r.ImGui_CalcTextSize(ctx, text)
    r.ImGui_DrawList_AddText(dl, x + (w - tw) / 2, y + (h - th) / 2, ink, text)
  end
  if hov and tip then r.ImGui_SetTooltip(ctx, tip) end
  return hit
end

-- a knob: the orange arc is the base value, the blue ring runs from the base to the value
-- that plays now (when modulated), with a dot at its end
local A0, A1 = math.pi * 0.75, math.pi * 2.25
function U.knob(dl, cx, cy, rad, base, cur, modded, hov, lo, hi)
  -- Bitwig: a grey body with a dark rim, the value as an orange arc OUTSIDE the body, a white
  -- pointer; modulation: the swept range dim blue on the same ring, the value now bright blue
  local ra = rad + 3
  r.ImGui_DrawList_PathArcTo(dl, cx, cy, ra, A0, A1, 24)
  r.ImGui_DrawList_PathStroke(dl, C.k_track, 0, 2.5)
  local ab = A0 + (A1 - A0) * base
  if base > 0.002 then
    r.ImGui_DrawList_PathArcTo(dl, cx, cy, ra, A0, ab, 0)
    r.ImGui_DrawList_PathStroke(dl, C.accent, 0, 2.5)
  end
  if modded and lo then
    lo, hi = H.clamp(lo, 0, 1), H.clamp(hi, 0, 1)
    if hi - lo > 0.002 then
      r.ImGui_DrawList_PathArcTo(dl, cx, cy, ra, A0 + (A1 - A0) * lo, A0 + (A1 - A0) * hi, 0)
      r.ImGui_DrawList_PathStroke(dl, C.mod_dim, 0, 2.5)
    end
  end
  r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, rad, C.k_edge, 24)
  r.ImGui_DrawList_AddCircleFilled(dl, cx, cy - 0.5, rad - 1.2, hov and C.k_body_hi or C.k_body, 24)
  local ca, sa = math.cos(ab), math.sin(ab)
  r.ImGui_DrawList_AddLine(dl, cx + ca * rad * 0.25, cy + sa * rad * 0.25, cx + ca * (rad - 2), cy + sa * (rad - 2), C.text, 2)
  if modded then
    local ac = A0 + (A1 - A0) * cur
    if math.abs(ac - ab) > 0.01 then
      r.ImGui_DrawList_PathArcTo(dl, cx, cy, ra, math.min(ab, ac), math.max(ab, ac), 0)
      r.ImGui_DrawList_PathStroke(dl, C.mod, 0, 2.5)
    end
    r.ImGui_DrawList_AddCircleFilled(dl, cx + math.cos(ac) * ra, cy + math.sin(ac) * ra, 2.6, C.mod, 8)
  end
end

-- the FX's power and window icons
function U.power(dl, cx, cy, col)
  r.ImGui_DrawList_PathArcTo(dl, cx, cy, 4.5, -math.pi * 0.3, math.pi * 1.3, 12)
  r.ImGui_DrawList_PathStroke(dl, col, 0, 1.5)
  r.ImGui_DrawList_AddLine(dl, cx, cy - 6, cx, cy - 1, col, 1.5)
end
function U.window(dl, cx, cy, col)
  r.ImGui_DrawList_AddRect(dl, cx - 5, cy - 4, cx + 5, cy + 4, col, 1, 0, 1.2)
  r.ImGui_DrawList_AddRectFilled(dl, cx - 5, cy - 4, cx + 5, cy - 2, col)
end
function U.plus(dl, cx, cy, col)
  r.ImGui_DrawList_AddLine(dl, cx - 6, cy, cx + 6, cy, col, 2)
  r.ImGui_DrawList_AddLine(dl, cx, cy - 6, cx, cy + 6, col, 2)
end

---------------------------------------------------------------- JSON (what the remote file needs)
-- false in an array = an empty slot, written as null
local J = {}
function J.str(v)
  return '"' .. v:gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' elseif c == '\\' then return '\\\\' elseif c == '\n' then return '\\n' end
    return string.format('\\u%04x', c:byte())
  end) .. '"'
end
function J.enc(v, ind)
  ind = ind or ""
  local t = type(v)
  if v == nil or v == false then return "null" end
  if v == true then return "true" end
  if t == "number" then
    if v == math.floor(v) and math.abs(v) < 2 ^ 53 then return string.format("%d", v) end
    return string.format("%.6g", v)
  end
  if t == "string" then return J.str(v) end
  local inner = ind .. "  "
  local out = {}
  if #v > 0 then
    for k = 1, #v do out[k] = inner .. J.enc(v[k], inner) end
    return "[\n" .. table.concat(out, ",\n") .. "\n" .. ind .. "]"
  end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = tostring(k) end
  if #keys == 0 then return "{}" end
  table.sort(keys)
  for n, k in ipairs(keys) do out[n] = inner .. J.str(k) .. ": " .. J.enc(v[k], inner) end
  return "{\n" .. table.concat(out, ",\n") .. "\n" .. ind .. "}"
end
function J.dec(s)
  local pos = 1
  local function ws() pos = s:find("[^ \t\r\n]", pos) or #s + 1 end
  local function str()
    local out, i = {}, pos + 1
    while true do
      local c = s:sub(i, i)
      if c == "" then error("json: open string") end
      if c == '"' then pos = i + 1; return table.concat(out) end
      if c == "\\" then
        local e = s:sub(i + 1, i + 1)
        if e == "u" then
          out[#out + 1] = utf8.char(tonumber(s:sub(i + 2, i + 5), 16) or 63)
          i = i + 6
        else
          out[#out + 1] = ({ b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" })[e] or e
          i = i + 2
        end
      else
        out[#out + 1] = c
        i = i + 1
      end
    end
  end
  local val
  function val()
    ws()
    local c = s:sub(pos, pos)
    if c == "{" then
      local t = {}
      pos = pos + 1
      ws()
      if s:sub(pos, pos) == "}" then pos = pos + 1; return t end
      while true do
        ws()
        local k = str()
        ws()
        pos = pos + 1                       -- the colon
        t[k] = val()
        ws()
        local d = s:sub(pos, pos)
        pos = pos + 1
        if d == "}" then return t end
        if d ~= "," then error("json: , or } expected at " .. pos) end
      end
    elseif c == "[" then
      local t, n = {}, 0
      pos = pos + 1
      ws()
      if s:sub(pos, pos) == "]" then pos = pos + 1; return t end
      while true do
        n = n + 1
        local v = val()
        if v == nil then v = false end
        t[n] = v
        ws()
        local d = s:sub(pos, pos)
        pos = pos + 1
        if d == "]" then return t end
        if d ~= "," then error("json: , or ] expected at " .. pos) end
      end
    elseif c == '"' then
      return str()
    elseif s:find("^true", pos) then pos = pos + 4; return true
    elseif s:find("^false", pos) then pos = pos + 5; return false
    elseif s:find("^null", pos) then pos = pos + 4; return nil
    end
    local num = s:match("^-?[%d%.eE%+%-]+", pos)
    if not num then error("json: bad value at " .. pos) end
    pos = pos + #num
    return tonumber(num)
  end
  return val()
end

---------------------------------------------------------------- remote controls
-- Pages of 8 knobs per PLUGIN (keyed by its original name, so a renamed FX and every other
-- instance share them), kept in Data/TK Theme Bit/remote_controls.json:
--   { "version": 1, "plugins": { "<original name>": { "pages": [ { "name": "Page 1",
--     "slots": [ { "p": 3, "n": "Frequency" }, null, ... 8 ] } ] } } }
-- A slot holds the parameter's index AND name: when a plugin update moves the index, the
-- name finds it again.
local RC = { file = r.GetResourcePath() .. "/Data/TK Theme Bit/remote_controls.json" }
function RC.load()
  local d
  local f = io.open(RC.file, "rb")
  if f then
    local text = f:read("*a")
    f:close()
    local ok, v = pcall(J.dec, text)
    if ok and type(v) == "table" then d = v else H.say("could not read " .. RC.file .. ": " .. tostring(v)) end
  end
  d = d or {}
  d.version = d.version or 1
  d.plugins = d.plugins or {}
  RC.data = d
end
function RC.save()
  r.RecursiveCreateDirectory(RC.file:match("^(.*)/"), 0)
  local f = io.open(RC.file, "wb")
  if not f then H.say("could not write " .. RC.file); return end
  f:write(J.enc(RC.data), "\n")
  f:close()
  S.rcres = {}
end
function RC.key(tr, i)
  local g = r.TrackFX_GetFXGUID(tr, i)
  local k = S.rckey[g]
  if k then return k end
  local ok, n = r.TrackFX_GetNamedConfigParm(tr, i, "original_name")
  if not ok or n == "" then n = select(2, r.TrackFX_GetFXName(tr, i, "")) end
  S.rckey[g] = n
  return n
end
function RC.plugin(tr, i, make)
  local k = RC.key(tr, i)
  local pl = RC.data.plugins[k]
  if not pl and make then
    pl = { pages = {} }
    RC.data.plugins[k] = pl
  end
  return pl
end
function RC.new_page(pl)
  local pg = { name = "Page " .. (#pl.pages + 1), slots = {} }
  for k = 1, 8 do pg.slots[k] = false end
  pl.pages[#pl.pages + 1] = pg
  return #pl.pages
end
function RC.cur(guid, pl)
  local n = pl and #pl.pages or 0
  local c = math.max(1, math.min(S.rcpage[guid] or 1, n))
  S.rcpage[guid] = c
  return c
end
-- the slot's parameter index now: the stored one while its name still matches, else by name
function RC.resolve(tr, i, guid, slot)
  if not slot then return nil end
  local c = F.params(tr, i, guid)
  local e = c.list[(slot.p or -1) + 1]
  if e and e[2] == slot.n then return slot.p end
  local key = guid .. "|" .. tostring(slot.n)
  local hit = S.rcres[key]
  if hit == nil then
    hit = false
    for _, e2 in ipairs(c.list) do
      if e2[2] == slot.n then hit = e2[1]; break end
    end
    S.rcres[key] = hit
  end
  return hit or nil
end
function RC.assign(tr, i, page, k, p)
  local pl = RC.plugin(tr, i, true)
  if #pl.pages == 0 then RC.new_page(pl) end
  page = math.max(1, math.min(page, #pl.pages))
  local name = select(2, r.TrackFX_GetParamName(tr, i, p, ""))
  pl.pages[page].slots[k] = { p = p, n = name }
  RC.save()
  return page
end
-- a parameter onto the first free slot of the page on show (a new page when it is full)
function RC.add(tr, i, guid, p)
  local pl = RC.plugin(tr, i, true)
  if #pl.pages == 0 then RC.new_page(pl) end
  local page = RC.cur(guid, pl)
  for k = 1, 8 do
    if not pl.pages[page].slots[k] then RC.assign(tr, i, page, k, p); return end
  end
  page = RC.new_page(pl)
  S.rcpage[guid] = page
  RC.assign(tr, i, page, 1, p)
end
-- the page filled with the next 8 parameters that are on no page yet
-- the plug-in's parameter groups, as many plug-ins name them: "VCF1:Cutoff", "VCC:Voices" (a
-- prefix before ':'), else a shared first word ("Filter 1 Cutoff", "Env1 Attack") when that
-- gives at least 3 groups of 2 or more. Returns { { name, { {p, name, label} ... } } ... } in
-- the plug-in's order, or nil when there are no groups to speak of.
local SKIP = { Bypass = true, Wet = true, Delta = true }
-- Bitwig's instrument pages by kind: from words in the parameter's name
local CATS = { "OSC1", "OSC2", "OSC3", "OSC4", "OSC", "MIX", "FILTER", "FILTER/EG", "AMP", "Envelope", "LFO", "FX", "Common" }
local function has(n, words)
  for _, w in ipairs(words) do if n:find(w) then return true end end
  return false
end
function RC.category(name)
  local n = " " .. name:lower():gsub("[_%-:/]", " ") .. " "
  local num = n:match("osc%a*%s*(%d)") or n:match("vco%s*(%d)")
  local env = has(n, { "attack", "decay", "sustain", "release", "%f[%a]env", "%f[%a]eg%f[%A]", "adsr", "%f[%a]hold%f[%A]" })
  local filt = has(n, { "filter", "cutoff", "%f[%a]cut%f[%A]", "reso", "%f[%a]res%f[%A]", "vcf", "%f[%a]q%f[%A]",
    "%f[%a][hlb]pf%f[%A]", "%f[%a]hp%f[%A]", "%f[%a]lp%f[%A]" })
  local amp = has(n, { "%f[%a]amp", "vca", "volume", "%f[%a]vol%f[%A]", "%f[%a]gain%f[%A]", "%f[%a]level%f[%A]", "velocity" })
  if filt and env then return "FILTER/EG" end
  if amp and env then return "AMP" end                     -- the amp envelope goes with AMP
  if num and has(n, { "osc", "vco" }) then return "OSC" .. num end
  if has(n, { "osc", "vco", "wave", "pitch", "tune", "detune", "semi", "%f[%a]fine%f[%A]", "unison", "%f[%a]sub%f[%A]",
    "noise", "pulse", "%f[%a]pw%f[%A]", "%f[%a]saw", "square", "%f[%a]sine", "%f[%a]tri%f[%A]", "%f[%a]glide", "porta" }) then
    return "OSC"
  end
  if filt then return "FILTER" end
  if env then return "Envelope" end
  if amp then return "AMP" end
  if has(n, { "lfo", "%f[%a]rate%f[%A]", "depth", "%f[%a]speed%f[%A]" }) then return "LFO" end
  if has(n, { "%f[%a]mix%f[%A]", "%f[%a]wet%f[%A]", "%f[%a]dry%f[%A]", "balance", "blend" }) then return "MIX" end
  if has(n, { "reverb", "delay", "chorus", "phaser", "flanger", "distort", "%f[%a]drive", "%f[%a]fx%f[%A]" }) then return "FX" end
  return "Common"
end
function RC.groups(tr, i, guid)
  local c = F.params(tr, i, guid)
  local function collect(split)
    local order, by, used = {}, {}, 0
    for _, e in ipairs(c.list) do
      if not SKIP[e[2]] then
        local g, rest = split(e[2])
        if g and rest and rest ~= "" then
          if not by[g] then by[g] = {}; order[#order + 1] = g end
          local t = by[g]
          t[#t + 1] = { e[1], e[2], rest }
          used = used + 1
        end
      end
    end
    local big = 0
    for _, g in ipairs(order) do if #by[g] >= 2 then big = big + 1 end end
    return order, by, used, big
  end
  -- 1: a prefix before ':'
  local order, by, used, big = collect(function(n) return n:match("^%s*([^:]+):%s*(.+)$") end)
  if big < 2 or used < #c.list / 2 then
    -- 2: the kind of control (OSC1, FILTER, AMP, Envelope ...), in Bitwig's order
    order, by, used = collect(function(n) return RC.category(n), (n:gsub("^%s*[^:]+:%s*", "")) end)
    local kinds = 0
    for _, g in ipairs(order) do if g ~= "Common" and #by[g] >= 2 then kinds = kinds + 1 end end
    if kinds >= 2 then
      -- a kind with one parameter joins Common (no near-empty pages)
      local common = by.Common or {}
      local keep = {}
      for _, g in ipairs(order) do
        if g ~= "Common" and #by[g] < 2 then
          for _, e in ipairs(by[g]) do common[#common + 1] = e end
        elseif g ~= "Common" then
          keep[#keep + 1] = g
        end
      end
      local rank = {}
      for k, g in ipairs(CATS) do rank[g] = k end
      table.sort(keep, function(a, b) return (rank[a] or 99) < (rank[b] or 99) end)
      local out = {}
      for _, g in ipairs(keep) do out[#out + 1] = { g, by[g] } end
      if #common > 0 then out[#out + 1] = { "Common", common } end
      return out
    end
    -- 3: the first word
    order, by, used, big = collect(function(n)
      local g, rest = n:match("^%s*(%S+%s+%d+)%s+(.+)$")     -- "Osc 1 Level": the group is "Osc 1"
      if g then return g, rest end
      return n:match("^%s*(%S+)%s+(.+)$")
    end)
    if big < 3 or used < #c.list / 2 then return nil end
  end
  local out = {}
  for _, g in ipairs(order) do
    if #by[g] >= 2 then out[#out + 1] = { g, by[g] } end
  end
  return out
end

-- pages from the groups: 8 per page, named after the group ("VCF1", "VCF1 2", ...), the knobs
-- labelled without the prefix. Groups that already have a page (same name) are left alone.
-- Returns the number of pages made.
function RC.autopages(tr, i, guid)
  local groups = RC.groups(tr, i, guid)
  if not groups then return 0 end
  local pl = RC.plugin(tr, i, true)
  local have = {}
  for _, pg in ipairs(pl.pages) do have[pg.name] = true end
  local made = 0
  for _, gr in ipairs(groups) do
    local list = gr[2]
    for start = 1, #list, 8 do
      local name = gr[1] .. (start > 1 and (" " .. ((start - 1) // 8 + 1)) or "")
      if not have[name] and #pl.pages < 64 then
        local pg = { name = name, slots = {} }
        for k = 1, 8 do
          local e = list[start + k - 1]
          pg.slots[k] = e and { p = e[1], n = e[2], label = e[3] } or false
        end
        pl.pages[#pl.pages + 1] = pg
        have[name] = true
        made = made + 1
      end
    end
  end
  if made > 0 then RC.save() end
  return made
end

function RC.fill(tr, i, guid, page)
  local pl = RC.plugin(tr, i, true)
  if #pl.pages == 0 then page = RC.new_page(pl) end
  local used = {}
  for _, pg in ipairs(pl.pages) do
    for k = 1, 8 do
      local sl = pg.slots[k]
      if sl then used[sl.n] = true end
    end
  end
  local c = F.params(tr, i, guid)
  local slots = pl.pages[page].slots
  local at = 1
  for _, e in ipairs(c.list) do
    while at <= 8 and slots[at] do at = at + 1 end
    if at > 8 then break end
    local n = e[2]
    if not used[n] and n ~= "Bypass" and n ~= "Wet" and n ~= "Delta" then
      slots[at] = { p = e[1], n = n }
      used[n] = true
    end
  end
  RC.save()
end

-- learning: a remote slot waits for a parameter touched in the plugin's own window (or a click
-- on a knob in the parameter list); then the next empty slot of that page waits
function RC.touch()
  if r.GetTouchedOrFocusedFX then
    local ok, ti, ii, _, fx, pa = r.GetTouchedOrFocusedFX(0)
    if ok then return ti, ii, fx, pa end
    return nil
  end
  local ok, tn, fx, pa = r.GetLastTouchedFX()      -- older REAPER: tracknumber 1-based, 0 = master
  if ok then return tn - 1, (fx >> 16) > 0 and 0 or -1, fx & 0xFFFF, pa end
end
function RC.snap()
  local a, b, c, d = RC.touch()
  return tostring(a) .. "," .. tostring(b) .. "," .. tostring(c) .. "," .. tostring(d)
end
function RC.learn(guid, page, k)
  S.learn = { guid = guid, page = page, slot = k, snap = RC.snap() }
  S.guid = guid
end
function RC.learned(tr, i, p)
  local L = S.learn
  local page = RC.assign(tr, i, L.page, L.slot, p)
  local pl = RC.plugin(tr, i)
  for k = L.slot + 1, 8 do
    if not pl.pages[page].slots[k] then
      S.learn = { guid = L.guid, page = page, slot = k, snap = RC.snap() }
      return
    end
  end
  S.learn = nil
end
function RC.poll(tr)
  local L = S.learn
  if not L then return end
  local i = F.index(tr, L.guid)
  if not i then S.learn = nil; return end
  local snap = RC.snap()
  if snap == L.snap then return end
  L.snap = snap
  local ti, ii, fx, pa = RC.touch()
  local my = tr == r.GetMasterTrack(0) and -1 or math.floor(r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")) - 1
  if ti == my and ii == -1 and fx == i and pa then RC.learned(tr, i, pa) end
end

-- Modulators live in a device's Modulators pane, as in Bitwig. In REAPER the JSFX sits at the
-- end of the track's chain (plink only works within one track); the device it belongs to is
-- kept in the track (P_EXT), and the row hides it.
function M.key(lg) return "P_EXT:TKBIT_MOD_" .. (lg:gsub("[{}]", "")) end
function M.add_lfo(tr, owner) return M.add_mod(tr, owner, "lfo") end
-- Every link by GUID (target FX, parameter, source FX), to put plink.effect right again after
-- FX were inserted, moved or deleted: whether or not REAPER renumbers the links itself, the
-- source stays the same FX.
function M.links_snap(tr)
  local out, n = {}, r.TrackFX_GetCount(tr)
  for i = 0, n - 1 do
    local g = r.TrackFX_GetFXGUID(tr, i)
    for p = 0, r.TrackFX_GetNumParams(tr, i) - 1 do
      if (F.cfg(tr, i, p, "plink.active") or 0) ~= 0 then
        local e = F.cfg(tr, i, p, "plink.effect") or -1
        if e >= 0 and e < n then out[#out + 1] = { tgt = g, p = p, src = r.TrackFX_GetFXGUID(tr, e) } end
      end
    end
  end
  return out
end
function M.links_fix(tr, snap)
  for _, e in ipairs(snap) do
    local ti, si = F.index(tr, e.tgt), F.index(tr, e.src)
    if ti and si and F.cfg(tr, ti, e.p, "plink.effect") ~= si then
      F.set(tr, ti, e.p, "plink.effect", si)
      H.say(("relinked FX #%d param %d to its source, now FX #%d"):format(ti + 1, e.p, si + 1))
    end
  end
end

-- a modulator: at the end of the chain, or (kinds that need the MIDI notes: m.first) at the
-- start, before the instrument eats them
function M.add_mod(tr, owner, kind)
  local m = MODS[kind]
  if not M.install(kind) then H.say("could not write " .. m.file); return end
  local snap = m.first and M.links_snap(tr)
  local pos = m.first and -1000 or -1
  r.Undo_BeginBlock2(0)
  local li = r.TrackFX_AddByName(tr, "JS:TK Theme Bit/" .. m.file, false, pos)
  if li < 0 then li = r.TrackFX_AddByName(tr, "JS:" .. m.desc, false, pos) end
  if snap then M.links_fix(tr, snap) end
  if li >= 0 then
    r.GetSetMediaTrackInfo_String(tr, M.key(r.TrackFX_GetFXGUID(tr, li)), owner, true)
    r.TrackFX_Show(tr, li, 2)                    -- no floating window (when REAPER auto-floats new FX)
  else
    H.say("TrackFX_AddByName could not add " .. m.file)
  end
  r.Undo_EndBlock2(0, "Devices: add " .. m.menu, -1)
  F.scan(tr, true)
  if li >= 0 then return li end
end
-- route LFO li to parameter p of FX ti: played = base + scale * (lfo - 0.5) (measured formula)
function M.route(tr, li, ti, p, scale, quiet, outp)
  local out = outp or F.param_index_cached(tr, li)
  local base = r.TrackFX_GetParamNormalized(tr, ti, p)
  if (F.cfg(tr, ti, p, "mod.active") or 0) ~= 0 then base = F.base_get(tr, ti, p) or base end
  F.set(tr, ti, p, "mod.active", 1)
  F.base_set(tr, ti, p, base)
  F.set(tr, ti, p, "plink.active", 1)
  F.set(tr, ti, p, "plink.effect", li)
  F.set(tr, ti, p, "plink.param", out)
  F.set(tr, ti, p, "plink.scale", scale)
  F.set(tr, ti, p, "plink.offset", M.bipolar(tr, li) and -0.5 or 0)
  if not quiet then r.Undo_OnStateChangeEx2(0, "Devices: route LFO", 2, -1) end
  F.scan(tr, true)
end
function M.unroute(tr, ti, p, quiet)
  local base = F.base_get(tr, ti, p)
  F.set(tr, ti, p, "plink.active", 0)
  F.set(tr, ti, p, "plink.effect", -1)
  F.set(tr, ti, p, "mod.active", 0)
  if base then r.TrackFX_SetParamNormalized(tr, ti, p, base) end
  if not quiet then
    r.Undo_OnStateChangeEx2(0, "Devices: remove modulation", 2, -1)
    F.scan(tr, true)
  end
end
function M.delete_lfo(tr, lg)
  local snap = M.links_snap(tr)
  r.Undo_BeginBlock2(0)
  for _, rt in ipairs(S.routes[lg] or {}) do
    local ti = F.index(tr, rt.tgt)
    if ti then M.unroute(tr, ti, rt.p, true) end
  end
  local li = F.index(tr, lg)
  if li then r.TrackFX_Delete(tr, li) end
  for _, n in ipairs(M.gslots_of(tr, lg)) do   -- its global Sends, and their slots
    local si = M.find_slot_fx(tr, "gsend", n)
    if si then r.TrackFX_Delete(tr, si) end
    r.SetProjExtState(0, GS, "slot" .. n, "")
  end
  M.links_fix(tr, snap)                       -- the FX after it moved up one
  r.GetSetMediaTrackInfo_String(tr, M.key(lg), "", true)
  r.Undo_EndBlock2(0, "Devices: delete modulator", -1)
  if S.route == lg then S.route = nil end
  F.scan(tr, true)
end
function H.track_by_guid(g)
  local m = r.GetMasterTrack(0)
  if r.GetTrackGUID(m) == g then return m end
  for k = 0, r.CountTracks(0) - 1 do
    local t = r.GetTrack(0, k)
    if r.GetTrackGUID(t) == g then return t end
  end
end
-- one of our JSFX at the end of tr's chain (no scan: tr need not be the track on show)
function M.add_fx(tr, kind)
  local m = MODS[kind]
  if not M.install(kind) then return end
  local fi = r.TrackFX_AddByName(tr, "JS:TK Theme Bit/" .. m.file, false, -1)
  if fi < 0 then fi = r.TrackFX_AddByName(tr, "JS:" .. m.desc, false, -1) end
  if fi >= 0 then
    r.TrackFX_Show(tr, fi, 2)
    return fi
  end
end
-- the slot of a source (track GUID | modulator GUID | output): its own, else (make) the first
-- free one of 64. The entry is "track|modulator|output|label".
function M.gslot(tg, lg, out, label, make)
  local want = tg .. "|" .. lg .. "|" .. tostring(out or "") .. "|"
  local free
  for n = 1, 64 do
    local _, v = r.GetProjExtState(0, GS, "slot" .. n)
    if v ~= "" then
      if v:sub(1, #want) == want then return n end
    elseif not free then
      free = n
    end
  end
  if make and free then
    r.SetProjExtState(0, GS, "slot" .. free, want .. (label or "Global"))
    return free
  end
end
function M.gslot_label(n)
  local _, v = r.GetProjExtState(0, GS, "slot" .. n)
  return v:match("|([^|]*)$") or "Global"
end
function M.find_slot_fx(tr, kind, n)
  for i = 0, r.TrackFX_GetCount(tr) - 1 do
    if F.mod_kind(tr, i) == kind then
      local sp = F.param_index_c(tr, i, "Slot")
      if sp and math.floor(r.TrackFX_GetParam(tr, i, sp) + 0.5) == n then return i end
    end
  end
end
function M.set_slot(tr, fi, n)
  local sp = F.param_index_c(tr, fi, "Slot")
  if sp then r.TrackFX_SetParamNormalized(tr, fi, sp, (n - 1) / 63) end
end
-- route a modulator on another track (src = { track, lg, out, label }) to parameter p of FX
-- ti on tr: slot, Send there, Global here, then an ordinary route from the Global. Returns
-- the Global's GUID (the routing source on this track from now on).
function M.route_global(src, tr, ti, p)
  local str = H.track_by_guid(src.track)
  local sli = str and F.index(str, src.lg)
  if not sli then return end
  local n = M.gslot(src.track, src.lg, src.out, src.label, true)
  if not n then H.say("all 64 global slots are in use"); return end
  local tg = r.TrackFX_GetFXGUID(tr, ti)
  r.Undo_BeginBlock2(0)
  local si = M.find_slot_fx(str, "gsend", n)
  if not si then
    si = M.add_fx(str, "gsend")
    local pin = si and F.param_index_c(str, si, "In")
    if pin then
      M.set_slot(str, si, n)
      F.set(str, si, pin, "mod.active", 1)
      F.set(str, si, pin, "mod.baseline", 0)
      F.set(str, si, pin, "plink.active", 1)
      F.set(str, si, pin, "plink.effect", F.index(str, src.lg))
      F.set(str, si, pin, "plink.param", src.out or F.param_index_cached(str, F.index(str, src.lg)))
      F.set(str, si, pin, "plink.scale", 1)
      F.set(str, si, pin, "plink.offset", 0)
    end
  end
  local ri = M.find_slot_fx(tr, "grecv", n)
  if not ri then
    ri = M.add_fx(tr, "grecv")
    if ri then
      M.set_slot(tr, ri, n)
      local bp = F.param_index_c(tr, ri, "Bipolar")
      local sli2 = F.index(str, src.lg)
      if bp and sli2 then r.TrackFX_SetParamNormalized(tr, ri, bp, M.bipolar(str, sli2) and 1 or 0) end
    end
  end
  r.Undo_EndBlock2(0, "Devices: global modulation", -1)
  ti = F.index(tr, tg)
  if not (ri and ti) then return end
  M.route(tr, ri, ti, p, 0, nil, F.param_index_cached(tr, ri))
  return r.TrackFX_GetFXGUID(tr, ri)
end
-- the slots of modulator lg on track tr (as source)
function M.gslots_of(tr, lg)
  local out, want = {}, r.GetTrackGUID(tr) .. "|" .. lg .. "|"
  for n = 1, 64 do
    local _, v = r.GetProjExtState(0, GS, "slot" .. n)
    if v:sub(1, #want) == want then out[#out + 1] = n end
  end
  return out
end

-- the LFO's Bipolar switch (an LFO from before it existed counts as bipolar)
function M.bipolar(tr, li)
  local bp = F.param_index_c(tr, li, "Bipolar")
  return not bp or r.TrackFX_GetParam(tr, li, bp) >= 0.5
end
-- Bipolar on: every route swings around its base (offset -0.5); off: up from it (offset 0)
function M.set_bipolar(tr, lg, on)
  local li = F.index(tr, lg)
  local bp = li and F.param_index_c(tr, li, "Bipolar")
  if not bp then return end
  r.TrackFX_SetParam(tr, li, bp, on and 1 or 0)
  for _, rt in ipairs(S.routes[lg] or {}) do
    local ti = F.index(tr, rt.tgt)
    if ti then F.set(tr, ti, rt.p, "plink.offset", on and -0.5 or 0) end
  end
  -- its Globals on other tracks follow: their Bipolar and their routes' offset
  for _, n in ipairs(M.gslots_of(tr, lg)) do
    for k = -1, r.CountTracks(0) - 1 do
      local t = k < 0 and r.GetMasterTrack(0) or r.GetTrack(0, k)
      local ri = M.find_slot_fx(t, "grecv", n)
      if ri then
        local rbp = F.param_index_c(t, ri, "Bipolar")
        if rbp then r.TrackFX_SetParamNormalized(t, ri, rbp, on and 1 or 0) end
        for e = 0, r.TrackFX_GetCount(t) - 1 do
          for q = 0, r.TrackFX_GetNumParams(t, e) - 1 do
            if (F.cfg(t, e, q, "plink.active") or 0) ~= 0 and F.cfg(t, e, q, "plink.effect") == ri then
              F.set(t, e, q, "plink.offset", on and -0.5 or 0)
            end
          end
        end
      end
    end
  end
  r.Undo_OnStateChangeEx2(0, "Devices: LFO bipolar", 2, -1)
end
-- the LFO's shape, 0..1 over one cycle (as the JSFX computes it)
local RND = { 0.25, 0.8, 0.45, 0.95, 0.1, 0.6, 0.35, 0.7 }
function M.shape(shape, t, curve)
  local v
  if shape == 0 then v = 0.5 + 0.5 * math.sin(2 * math.pi * t)
  elseif shape == 1 then v = t < 0.5 and 2 * t or 2 - 2 * t
  elseif shape == 2 then v = t
  elseif shape == 3 then v = t < 0.5 and 1 or 0
  else v = RND[math.min(8, math.floor(t * 8) + 1)] end
  curve = curve or 0
  if curve > 0.001 then v = v ^ (1 + 3 * curve) elseif curve < -0.001 then v = 1 - (1 - v) ^ (1 - 3 * curve) end
  return v
end
-- an LFO's shape and curve, as its sliders hold them
function M.look(tr, li)
  local shp, cv = F.param_index_c(tr, li, "Shape"), F.param_index_c(tr, li, "Curve")
  return shp and math.floor(r.TrackFX_GetParam(tr, li, shp) + 0.5) or 0, cv and r.TrackFX_GetParam(tr, li, cv) or 0
end
-- the modulation amount of parameter p when an LFO drives it, else nil
-- the range an LFO sweeps on parameter p (0..1), for the knob's dim arc; nil when none
function D.span(modded, tr, i, p, base)
  if not modded or (F.cfg(tr, i, p, "plink.active") or 0) == 0 then return nil end
  local sc, off = F.cfg(tr, i, p, "plink.scale") or 0, F.cfg(tr, i, p, "plink.offset") or 0
  local a, b = base + sc * off, base + sc * (1 + off)
  return math.min(a, b), math.max(a, b)
end
function F.depth(tr, i, p)
  if (F.cfg(tr, i, p, "plink.active") or 0) == 0 then return nil end
  return F.cfg(tr, i, p, "plink.scale")
end

-- the menu items a parameter gets wherever it is right-clicked (the list, the joker, a slot)
function M.menu_items(tr, guid, p, modded)
  local ti = F.index(tr, guid)
  if not ti then return end
  local src = modded and (F.cfg(tr, ti, p, "plink.active") or 0) ~= 0 and F.cfg(tr, ti, p, "plink.effect") or nil
  if src and src >= 0 and src < r.TrackFX_GetCount(tr) then
    U.text_col(C.dim, "MODULATION ROUTINGS")
    local d = F.cfg(tr, ti, p, "plink.scale") or 0
    local sname = F.name(tr, src)
    if F.mod_kind(tr, src) == "grecv" then
      local sp = F.param_index_c(tr, src, "Slot")
      sname = "Global: " .. M.gslot_label(sp and math.floor(r.TrackFX_GetParam(tr, src, sp) + 0.5) or 1)
    end
    if r.ImGui_MenuItem(ctx, ("Remove   %s  (%+d %%)"):format(sname, math.floor(d * 100 + 0.5))) then
      M.unroute(tr, ti, p)
    end
  else
    if modded then U.text_col(C.dim, "(modulated by REAPER's own LFO/ACS)") end
    if r.ImGui_MenuItem(ctx, "Modulate with a new LFO") then
      local owner = S.lfo_owner[guid] or guid       -- a modulator's knob: its device owns the new LFO
      local li = M.add_lfo(tr, owner)
      ti = F.index(tr, guid)
      if li and ti then M.route(tr, li, ti, p, 0.5); S.vm[owner] = true end
    end
  end
end

---------------------------------------------------------------- the vertical names (a stroke font)
-- ReaImGui can't rotate text, so the device and track names are drawn with lines, reading
-- upwards as Bitwig's: a 4 x 6 grid per letter (upper case, digits, a few signs).
local O_ = { 1,0, 3,0, 4,1, 4,5, 3,6, 1,6, 0,5, 0,1, 1,0 }
local P_ = { 0,6, 0,0, 3,0, 4,1, 4,2, 3,3, 0,3 }
local GLYPH = {
  A = { { 0,6, 0,2, 2,0, 4,2, 4,6 }, { 0,3.5, 4,3.5 } },
  B = { { 0,6, 0,0, 3,0, 4,1, 4,2, 3,3, 0,3 }, { 3,3, 4,4, 4,5, 3,6, 0,6 } },
  C = { { 4,1, 3,0, 1,0, 0,1, 0,5, 1,6, 3,6, 4,5 } },
  D = { { 0,0, 0,6, 3,6, 4,5, 4,1, 3,0, 0,0 } },
  E = { { 4,0, 0,0, 0,6, 4,6 }, { 0,3, 3,3 } },
  F = { { 4,0, 0,0, 0,6 }, { 0,3, 3,3 } },
  G = { { 4,1, 3,0, 1,0, 0,1, 0,5, 1,6, 3,6, 4,5, 4,3, 2,3 } },
  H = { { 0,0, 0,6 }, { 4,0, 4,6 }, { 0,3, 4,3 } },
  I = { { 1,0, 3,0 }, { 2,0, 2,6 }, { 1,6, 3,6 } },
  J = { { 4,0, 4,5, 3,6, 1,6, 0,5 } },
  K = { { 0,0, 0,6 }, { 4,0, 0,4 }, { 1.5,2.6, 4,6 } },
  L = { { 0,0, 0,6, 4,6 } },
  M = { { 0,6, 0,0, 2,3, 4,0, 4,6 } },
  N = { { 0,6, 0,0, 4,6, 4,0 } },
  O = { O_ },
  P = { P_ },
  Q = { O_, { 2.5,4.5, 4,6 } },
  R = { P_, { 2,3, 4,6 } },
  S = { { 4,1, 3,0, 1,0, 0,1, 0,2, 1,3, 3,3, 4,4, 4,5, 3,6, 1,6, 0,5 } },
  T = { { 0,0, 4,0 }, { 2,0, 2,6 } },
  U = { { 0,0, 0,5, 1,6, 3,6, 4,5, 4,0 } },
  V = { { 0,0, 2,6, 4,0 } },
  W = { { 0,0, 1,6, 2,3, 3,6, 4,0 } },
  X = { { 0,0, 4,6 }, { 4,0, 0,6 } },
  Y = { { 0,0, 2,3, 4,0 }, { 2,3, 2,6 } },
  Z = { { 0,0, 4,0, 0,6, 4,6 } },
  ["0"] = { O_, { 4,1, 0,5 } },
  ["1"] = { { 1,1, 2,0, 2,6 }, { 1,6, 3,6 } },
  ["2"] = { { 0,1, 1,0, 3,0, 4,1, 4,2, 0,6, 4,6 } },
  ["3"] = { { 0,1, 1,0, 3,0, 4,1, 4,2, 3,3, 1.5,3 }, { 3,3, 4,4, 4,5, 3,6, 1,6, 0,5 } },
  ["4"] = { { 3,6, 3,0, 0,4, 4,4 } },
  ["5"] = { { 4,0, 0,0, 0,3, 3,3, 4,4, 4,5, 3,6, 0,6 } },
  ["6"] = { { 3,0, 1,0, 0,1, 0,5, 1,6, 3,6, 4,5, 4,4, 3,3, 0,3 } },
  ["7"] = { { 0,0, 4,0, 1.5,6 } },
  ["8"] = { { 1,0, 3,0, 4,1, 4,2, 3,3, 1,3, 0,2, 0,1, 1,0 }, { 1,3, 0,4, 0,5, 1,6, 3,6, 4,5, 4,4, 3,3 } },
  ["9"] = { { 4,3, 1,3, 0,2, 0,1, 1,0, 3,0, 4,1, 4,5, 3,6, 1,6 } },
  ["-"] = { { 0.5,3, 3.5,3 } }, ["."] = { { 2,5.4, 2,6 } }, ["_"] = { { 0,6, 4,6 } },
  ["/"] = { { 0,6, 4,0 } }, ["("] = { { 3,0, 1.5,1.5, 1.5,4.5, 3,6 } }, [")"] = { { 1,0, 2.5,1.5, 2.5,4.5, 1,6 } },
  [":"] = { { 2,1.5, 2,2.1 }, { 2,4.5, 2,5.1 } }, ["+"] = { { 2,1.5, 2,4.5 }, { 0.5,3, 3.5,3 } },
  ["'"] = { { 2,0, 2,1.5 } }, ["&"] = { { 2,1.5, 2,4.5 }, { 0.5,3, 3.5,3 } },
}
-- the name centred between y0 (top) and y1 (bottom), reading upwards
-- The names in the real font, turned as Bitwig's: ReaImGui can't rotate text, so the name is
-- drawn once (white, bold system font) into a LICE bitmap with the JS extension, its black made
-- transparent, and the image drawn on its side with AddImageQuad, tinted. Kept per name. Without
-- the JS extension (or CreateImageFromLICE) the stroke font below is used.
U.vimg, U.vimg_n = {}, 0
function U.textimg(s)
  local hit = U.vimg[s]
  if hit ~= nil then return hit or nil end
  if not (r.JS_LICE_CreateBitmap and r.JS_GDI_CreateFont and r.ImGui_CreateImageFromLICE) then
    U.vimg[s] = false
    return nil
  end
  local ok, res = pcall(function()
    if not U.vfont then
      local face = r.GetOS():find("Win") and "Segoe UI" or "Arial"
      U.vgdi = r.JS_GDI_CreateFont(-12, 700, 0, false, false, false, face)
      U.vfont = r.JS_LICE_CreateFont()
      r.JS_LICE_SetFontFromGDI(U.vfont, U.vgdi, "")
      r.JS_LICE_SetFontColor(U.vfont, 0xFFFFFFFF)
    end
    local w, h = 9 * #s + 12, 16
    local bm = r.JS_LICE_CreateBitmap(true, w, h)
    r.JS_LICE_Clear(bm, 0xFF000000)
    r.JS_LICE_DrawText(bm, U.vfont, s, #s, 1, 0, w, h)
    -- black -> transparent: white with the brightness as alpha; the text's true width
    local right = 0
    for py = 0, h - 1 do
      for px = 0, w - 1 do
        local a = (r.JS_LICE_GetPixel(bm, px, py) >> 16) & 0xFF
        r.JS_LICE_PutPixel(bm, px, py, (a << 24) | 0xFFFFFF, 1, "COPY")
        if a > 24 and px > right then right = px end
      end
    end
    local img = r.ImGui_CreateImageFromLICE(bm)
    r.JS_LICE_DestroyBitmap(bm)
    r.ImGui_Attach(ctx, img)
    return { img = img, w = w, h = h, tw = right + 2 }
  end)
  if not ok or not res then H.say("name image failed: " .. tostring(res)); res = false end
  if U.vimg_n > 300 then U.vimg, U.vimg_n = {}, 0 end
  U.vimg[s], U.vimg_n = res, U.vimg_n + 1
  return res or nil
end

-- the name centred between y0 (top) and y1 (bottom), reading upwards; x + 4.5 is its centre line
function U.vcenter(dl, x, y0, y1, s, col, sc, th)
  local room = y1 - y0
  s = s:upper()
  local im = room > 8 and U.textimg(s)
  if im then
    local cx = x + 4.5
    local len = math.min(room, im.tw)
    local ybot = (y0 + y1) / 2 + len / 2
    local u1 = len / im.w                        -- cut at the room when the name is longer
    local hx = im.h / 2
    -- the image's top edge faces left (turned a quarter anticlockwise, as Bitwig's)
    r.ImGui_DrawList_AddImageQuad(dl, im.img,
      cx - hx, ybot, cx - hx, ybot - len, cx + hx, ybot - len, cx + hx, ybot,
      0, 0, u1, 0, u1, 1, 0, 1, col)
    return
  end
  local len = math.min(room, #s * 5.4 * sc - 1.4 * sc)
  U.vtext(dl, x, (y0 + y1) / 2 + len / 2, room, s, col, sc, th)
end
-- x: the left edge (the letters' tops), y: where the text starts (its bottom), len: room upwards
function U.vtext(dl, x, y, len, s, col, sc, th)
  local adv = 5.4 * sc
  s = s:upper()
  local n = math.floor((len + 1.4 * sc) / adv)
  if n < 1 then return end
  if #s > n then s = s:sub(1, math.max(1, n - 1)) .. "." end
  local pen = 0
  for k = 1, #s do
    local g = GLYPH[s:sub(k, k)]
    if g then
      for _, st in ipairs(g) do
        for m = 1, #st, 2 do r.ImGui_DrawList_PathLineTo(dl, x + st[m + 1] * sc, y - pen - st[m] * sc) end
        r.ImGui_DrawList_PathStroke(dl, col, 0, th)
      end
    end
    pen = pen + adv
  end
end

---------------------------------------------------------------- icons
function U.i_wifi(dl, cx, cy, col)
  r.ImGui_DrawList_AddCircleFilled(dl, cx, cy + 5, 1.8, col, 8)
  for k = 1, 3 do
    r.ImGui_DrawList_PathArcTo(dl, cx, cy + 5, 1.5 + k * 3, -math.pi * 0.77, -math.pi * 0.23, 10)
    r.ImGui_DrawList_PathStroke(dl, col, 0, 1.6)
  end
end
function U.arrow(dl, cx, cy, dir, col)
  r.ImGui_DrawList_AddTriangleFilled(dl, cx - 3 * dir, cy - 4, cx - 3 * dir, cy + 4, cx + 3 * dir, cy, col)
end
function U.i_knob(dl, cx, cy, col, on)
  if on then r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, 7, col, 16) end
  r.ImGui_DrawList_AddCircle(dl, cx, cy, 6, on and 0x141414FF or col, 16, 1.5)
  r.ImGui_DrawList_AddLine(dl, cx, cy, cx - 3, cy + 3, on and 0x141414FF or col, 1.5)
end
function U.i_list(dl, cx, cy, col)
  for k = -1, 1 do r.ImGui_DrawList_AddLine(dl, cx - 5, cy + k * 3.5, cx + 5, cy + k * 3.5, col, 1.5) end
end

---------------------------------------------------------------- remote controls on a device
-- one remote slot: a knob with its label; empty = "+" (click to learn)
function D.slot(tr, i, guid, pl, page, k, x, y, mods, dl)
  local pg = pl and pl.pages[page]
  local slot = pg and pg.slots[k] or nil
  local p = RC.resolve(tr, i, guid, slot)
  local learning = S.learn and S.learn.guid == guid and S.learn.page == page and S.learn.slot == k
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  r.ImGui_InvisibleButton(ctx, "##s" .. k, SLOT, SH)
  local hov, act = r.ImGui_IsItemHovered(ctx), r.ImGui_IsItemActive(ctx)
  local cx, cy, ly = x + SLOT / 2, y + 19, y + 39
  if r.ImGui_IsItemClicked(ctx, 1) then
    S.guid = guid
    S.rcmenu = { guid = guid, page = page, slot = k, p = p, open = true }
  end
  if learning then
    local a = math.floor(140 + 115 * math.sin(r.time_precise() * 8))
    r.ImGui_DrawList_AddCircle(dl, cx, cy, 17, (C.accent & 0xFFFFFF00) | a, 24, 2)
    local tw = r.ImGui_CalcTextSize(ctx, "learn")
    r.ImGui_DrawList_AddText(dl, cx - tw / 2, ly, C.accent, "learn")
    if r.ImGui_IsItemClicked(ctx, 0) then S.learn = nil end
    if hov then r.ImGui_SetTooltip(ctx, "Move a parameter in the plugin's window, or click one in the list.\nClick (or Esc) to stop.") end
    return
  end
  if not slot then
    U.i_wifi(dl, cx, cy, hov and C.text or C.mod)        -- Bitwig marks an unassigned control so
    if r.ImGui_IsItemClicked(ctx, 0) then
      local pl2 = RC.plugin(tr, i, true)
      if #pl2.pages == 0 then RC.new_page(pl2); RC.save() end
      RC.learn(guid, page, k)
    end
    if hov then r.ImGui_SetTooltip(ctx, "Click to learn: then move a parameter in the plugin's window") end
    return
  end
  if not p then
    r.ImGui_DrawList_AddCircle(dl, cx, cy, 14, C.bad, 20, 1)
    local t = H.fit(slot.n or "?", SLOT - 2)
    local tw = r.ImGui_CalcTextSize(ctx, t)
    r.ImGui_DrawList_AddText(dl, cx - tw / 2, ly, C.bad, t)
    if hov then r.ImGui_SetTooltip(ctx, (slot.n or "?") .. "\nnot found in this plugin (right-click: learn or clear)") end
    return
  end
  local modded = mods[p]
  local cur = r.TrackFX_GetParamNormalized(tr, i, p)
  local base = modded and (F.base_get(tr, i, p) or cur) or cur
  if r.ImGui_IsItemActivated(ctx) then
    S.guid = guid
    D.route_hit(tr, i, p)
  end
  if act then base, cur = D.drag(tr, i, p, base, cur, modded, slot.n) end
  if r.ImGui_IsItemDeactivated(ctx) and S.drag then
    r.Undo_OnStateChangeEx2(0, "Devices: " .. S.drag, 2, -1)
    S.drag = nil
  end
  U.knob(dl, cx, cy, 14, base, cur, modded, hov, D.span(modded, tr, i, p, base))
  local t, col = slot.label or slot.n, modded and C.mod or C.label
  if act or hov then t, col = select(2, r.TrackFX_GetFormattedParamValue(tr, i, p, "")), C.value end
  t = H.fit(t, SLOT - 2)
  local tw = r.ImGui_CalcTextSize(ctx, t)
  r.ImGui_DrawList_AddText(dl, cx - tw / 2, ly, col, t)
  if hov and not act then r.ImGui_SetTooltip(ctx, slot.n .. (modded and "\n(modulated)" or "")) end
end

local RPW = 4 * SLOT + 20            -- the remote controls pane's width (4 x 2, as Bitwig)
-- Bitwig's Remote Controls pane (opened from the strip): the page bar, then 8 slots, 2 x 4
-- the pages the pane can show: the plug-in's own (learned, editable), then one per modulator of
-- this device (fixed controls, as Bitwig's modulator pages)
function RC.entries(tr, i, guid)
  local pl = RC.plugin(tr, i)
  local list = {}
  for k = 1, pl and #pl.pages or 0 do list[#list + 1] = { kind = "p", k = k, name = pl.pages[k].name } end
  local count = {}
  for _, lg in ipairs(S.owned[guid] or {}) do
    local li = F.index(tr, lg)
    local mk = li and F.mod_kind(tr, li) or "lfo"
    count[mk] = (count[mk] or 0) + 1
    if mk == "lfo" then list[#list + 1] = { kind = "m", lg = lg, name = MODS[mk].label .. " " .. count[mk] } end
  end
  return pl, list
end
function RC.sel(guid, pl, list)
  local m = S.rcmod[guid]
  if m then
    for n, e in ipairs(list) do if e.kind == "m" and e.lg == m then return n end end
    S.rcmod[guid] = nil
  end
  if pl and #pl.pages > 0 then return RC.cur(guid, pl) end
  for n, e in ipairs(list) do if e.kind == "m" then return n end end    -- no pages: the first modulator
  return 0
end
function RC.go(guid, e)
  if e.kind == "m" then S.rcmod[guid] = e.lg else S.rcmod[guid] = nil; S.rcpage[guid] = e.k end
end

-- a knob on a modulator page: drags the JSFX parameter p
-- (a modulator's knob is a parameter like any other: another modulator can be routed to it,
-- as in Bitwig - click its routing button, then this knob, and drag)
function D.mknob(tr, li, p, label, x, y, dl)
  dl = dl or r.ImGui_GetWindowDrawList(ctx)
  local lg = r.TrackFX_GetFXGUID(tr, li)
  local modded = (S.mods[lg] or {})[p]
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  r.ImGui_InvisibleButton(ctx, "##mk" .. p, SLOT, SH)
  local hov, act = r.ImGui_IsItemHovered(ctx), r.ImGui_IsItemActive(ctx)
  local cur = r.TrackFX_GetParamNormalized(tr, li, p)
  local base = modded and (F.base_get(tr, li, p) or cur) or cur
  if r.ImGui_IsItemActivated(ctx) then D.route_hit(tr, li, p) end
  if act then base, cur = D.drag(tr, li, p, base, cur, modded, label) end
  if r.ImGui_IsItemDeactivated(ctx) and S.drag then
    r.Undo_OnStateChangeEx2(0, "Devices: " .. S.drag, 2, -1)
    S.drag = nil
  end
  if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) and not S.route then
    local def = ({ Phase = 0, Curve = 0.5, Amount = 1, Smooth = 0, Gain = 0.5, Value = 0, Glide = 0, Velocity = 0.5,
      Sustain = 0.6, ["Macro 1"] = 0, ["Macro 2"] = 0, ["Macro 3"] = 0, ["Macro 4"] = 0 })[label]
    if def then
      if modded then F.base_set(tr, li, p, def) else r.TrackFX_SetParamNormalized(tr, li, p, def) end
    end
  end
  if r.ImGui_IsItemClicked(ctx, 1) then r.ImGui_OpenPopup(ctx, "##mkmenu" .. p) end
  if r.ImGui_BeginPopup(ctx, "##mkmenu" .. p) then
    U.text_col(C.dim, label)
    r.ImGui_Separator(ctx)
    M.menu_items(tr, lg, p, modded)
    r.ImGui_EndPopup(ctx)
  end
  U.knob(dl, x + SLOT / 2, y + 19, 14, base, cur, modded, hov, D.span(modded, tr, li, p, base))
  local t, col = label, modded and C.mod or C.label
  if hov or act then t, col = select(2, r.TrackFX_GetFormattedParamValue(tr, li, p, "")), C.value end
  t = H.fit(t, SLOT - 2)
  local tw = r.ImGui_CalcTextSize(ctx, t)
  r.ImGui_DrawList_AddText(dl, x + (SLOT - tw) / 2, y + 39, col, t)
end

-- a chooser on a modulator page: a grey box with the choice (text, or draw(dl, x, y, w, h)) and
-- a small triangle; click = the list
function D.mchoose(tr, li, p, label, x, y, items, draw, dl)
  local cur = math.floor(r.TrackFX_GetParam(tr, li, p) + 0.5)
  local bx, by, bw, bh = x + 4, y + 9, SLOT - 8, 20
  r.ImGui_SetCursorScreenPos(ctx, bx, by)
  if r.ImGui_InvisibleButton(ctx, "##mc" .. p, bw, bh) then r.ImGui_OpenPopup(ctx, "##mcp" .. p) end
  local hov = r.ImGui_IsItemHovered(ctx)
  r.ImGui_DrawList_AddRectFilled(dl, bx, by, bx + bw, by + bh, hov and C.k_body_hi or C.box, 3)
  if draw then
    draw(dl, bx + 4, by + 3, bw - 16, bh - 6, cur)
  else
    local t = H.fit(items[cur + 1] or "?", bw - 14)
    local _, th = r.ImGui_CalcTextSize(ctx, t)
    r.ImGui_DrawList_AddText(dl, bx + 5, by + (bh - th) / 2, C.text, t)
  end
  r.ImGui_DrawList_AddTriangleFilled(dl, bx + bw - 10, by + 8, bx + bw - 4, by + 8, bx + bw - 7, by + 12, C.dim)
  local tw = r.ImGui_CalcTextSize(ctx, label)
  r.ImGui_DrawList_AddText(dl, x + (SLOT - tw) / 2, y + 39, C.label, label)
  if hov then r.ImGui_SetTooltip(ctx, label .. ": " .. (items[cur + 1] or "?")) end
  if r.ImGui_BeginPopup(ctx, "##mcp" .. p) then
    for k, nm in ipairs(items) do
      if r.ImGui_MenuItem(ctx, nm, nil, cur == k - 1) then
        r.TrackFX_SetParam(tr, li, p, k - 1)
        r.Undo_OnStateChangeEx2(0, "Devices: LFO " .. label, 2, -1)
      end
    end
    r.ImGui_EndPopup(ctx)
  end
end

-- a modulator page, in Bitwig's order: Rate, Mode, Timebase, Phase / Waveform, Bipolar, Curve, Amount
local TBASE = { "4/1", "2/1", "1/1", "1/2", "1/4", "1/8", "1/16", "1/32" }
local CHANS = { "Omni", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13", "14", "15", "16" }
MODS.all = { "gsend", "grecv" }
for _, k in ipairs(MODS.order) do MODS.all[#MODS.all + 1] = k end
-- each modulator's page: { kind of control, the JSFX parameter's name, the label, (choices) }
local PAGES = {
  lfo = { { "knob", "Rate (Hz)", "Rate" }, { "choose", "Mode", "Mode", { "Free", "Sync" } },
    { "choose", "Timebase", "Timebase", TBASE }, { "knob", "Phase", "Phase" },
    { "wave", "Shape", "Waveform" }, { "bip" }, { "knob", "Curve", "Curve" }, { "knob", "Amount", "Amount" } },
  steps = { { "knob", "Steps", "Steps" }, { "choose", "Timebase", "Timebase", TBASE },
    { "knob", "Smooth", "Smooth" }, { "bip" } },
  random = { { "knob", "Rate (Hz)", "Rate" }, { "choose", "Mode", "Mode", { "Free", "Sync" } },
    { "choose", "Timebase", "Timebase", TBASE }, { "knob", "Smooth", "Smooth" },
    { "bip" }, { "knob", "Amount", "Amount" } },
  follower = { { "knob", "Rise (ms)", "Rise" }, { "knob", "Fall (ms)", "Fall" },
    { "knob", "Gain (dB)", "Gain" }, { "choose", "Input", "Input", { "Main", "Sidechain 3/4" } },
    { "bip" }, { "knob", "Amount", "Amount" } },
  macro = { { "knob", "Value", "Value" }, { "bip" }, { "knob", "Amount", "Amount" } },
  adsr = { { "knob", "Attack (ms)", "Attack" }, { "knob", "Decay (ms)", "Decay" }, { "knob", "Sustain", "Sustain" },
    { "knob", "Release (ms)", "Release" }, { "knob", "Velocity", "Velocity" }, { "choose", "Single", "Single", { "Off", "On" } },
    { "bip" }, { "knob", "Amount", "Amount" } },
  midi = { { "choose", "Type", "Type", { "CC", "Pitch Bend", "Aftertouch", "Velocity" } }, { "knob", "CC", "CC" },
    { "choose", "Channel", "Channel", CHANS }, { "knob", "Smooth", "Smooth" }, { "bip" }, { "knob", "Amount", "Amount" } },
  keytrack = { { "knob", "Low note", "Low" }, { "knob", "High note", "High" }, { "knob", "Glide", "Glide" },
    { "bip" }, { "knob", "Amount", "Amount" } },
  macro4 = { { "knob", "Macro 1", "Macro 1" }, { "knob", "Macro 2", "Macro 2" }, { "knob", "Macro 3", "Macro 3" },
    { "knob", "Macro 4", "Macro 4" }, { "bip" } },
  button = { { "toggle", "Button", "Button" }, { "choose", "Mode", "Mode", { "Toggle", "Momentary" } },
    { "knob", "Smooth", "Smooth" }, { "bip" }, { "knob", "Amount", "Amount" } },
}

-- a modulator page: its controls 4 x 2 in Bitwig's order; Steps gets its step editor below
function D.modpage(tr, lg, x, y, w, dl)
  local li = F.index(tr, lg)
  if not li then return end
  local kind = F.mod_kind(tr, li) or "lfo"
  local sx = x + (w - 4 * SLOT) / 2
  local function at(k) return sx + ((k - 1) % 4) * SLOT, y + ((k - 1) // 4) * (SH + 2) end
  local mode = F.param_index_c(tr, li, "Mode")
  local synced = mode and r.TrackFX_GetParam(tr, li, mode) >= 0.5
  for k, it in ipairs(PAGES[kind]) do
    local cx, cy = at(k)
    local p = it[2] and F.param_index_c(tr, li, it[2])
    if it[1] == "bip" then
      local bp = F.param_index_c(tr, li, "Bipolar")
      if bp then
        local bip = M.bipolar(tr, li)
        r.ImGui_SetCursorScreenPos(ctx, cx + 4, cy + 9)
        if U.key("bip" .. lg, "\u{00B1}", bip, SLOT - 8, 20, bip and "Bipolar: swings around the value" or "Unipolar: goes up from the value") then
          M.set_bipolar(tr, lg, not bip)
        end
        local tw = r.ImGui_CalcTextSize(ctx, "Bipolar")
        r.ImGui_DrawList_AddText(dl, cx + (SLOT - tw) / 2, cy + 39, C.label, "Bipolar")
      else
        r.ImGui_DrawList_AddText(dl, cx + 10, cy + 14, C.dim, "(old)")
      end
    elseif not p then
      r.ImGui_DrawList_AddText(dl, cx + 10, cy + 14, C.dim, "(old)")
    elseif it[1] == "knob" then
      D.mknob(tr, li, p, (it[2] == "Rate (Hz)" and synced) and "(Rate)" or it[3], cx, cy, dl)
    elseif it[1] == "choose" then
      D.mchoose(tr, li, p, it[3], cx, cy, it[4], nil, dl)
    elseif it[1] == "toggle" then
      local on = r.TrackFX_GetParam(tr, li, p) >= 0.5
      r.ImGui_SetCursorScreenPos(ctx, cx + 4, cy + 9)
      if U.key("tg" .. lg .. p, on and "On" or "Off", on, SLOT - 8, 20) then
        r.TrackFX_SetParam(tr, li, p, on and 0 or 1)
        r.Undo_OnStateChangeEx2(0, "Devices: " .. it[3], 2, -1)
      end
      local tw = r.ImGui_CalcTextSize(ctx, it[3])
      r.ImGui_DrawList_AddText(dl, cx + (SLOT - tw) / 2, cy + 39, C.label, it[3])
    elseif it[1] == "wave" then
      local _, curve = M.look(tr, li)
      D.mchoose(tr, li, p, it[3], cx, cy, SHAPES, function(d, bx, by, bw, bh, cur)
        for t8 = 0, 16 do
          local t = t8 / 16
          r.ImGui_DrawList_PathLineTo(d, bx + t * bw, by + bh - M.shape(cur, t, curve) * bh)
        end
        r.ImGui_DrawList_PathStroke(d, C.text, 0, 1.4)
      end, dl)
    end
  end
  if kind == "steps" then D.steps_editor(tr, li, sx + 2, y + SH + 4, 4 * SLOT - 4, SH - 6, dl) end
end

-- the Steps modulator's steps: bars to draw with the mouse, the step playing now in orange
function M.steps(tr, li)
  local ns, pp = F.param_index_c(tr, li, "Steps"), F.param_index_c(tr, li, "Position")
  local n = ns and math.max(1, math.floor(r.TrackFX_GetParam(tr, li, ns) + 0.5)) or 8
  local pos = pp and math.floor(r.TrackFX_GetParam(tr, li, pp) + 0.5) or -1
  return n, pos
end
function D.steps_editor(tr, li, x, y, w, h, dl)
  local n, pos = M.steps(tr, li)
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, C.headbox, 3)
  r.ImGui_DrawList_AddRect(dl, x, y, x + w, y + h, C.pane_edge, 3, 0, 1)
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  r.ImGui_InvisibleButton(ctx, "##steps", w, h)
  local bw = (w - 4) / n
  if r.ImGui_IsItemActive(ctx) then
    local mx, my = r.ImGui_GetMousePos(ctx)
    local k = math.max(1, math.min(n, math.floor((mx - x - 2) / bw) + 1))
    local p = F.param_index_c(tr, li, "Step " .. k)
    if p then r.TrackFX_SetParam(tr, li, p, H.clamp(1 - (my - y - 2) / (h - 4), 0, 1)) end
  end
  if r.ImGui_IsItemDeactivated(ctx) then r.Undo_OnStateChangeEx2(0, "Devices: steps", 2, -1) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Draw the steps with the mouse") end
  if M.bipolar(tr, li) then
    r.ImGui_DrawList_AddLine(dl, x + 2, y + h / 2, x + w - 2, y + h / 2, C.pane_edge, 1)
  end
  for k = 1, n do
    local p = F.param_index_c(tr, li, "Step " .. k)
    local v = p and r.TrackFX_GetParam(tr, li, p) or 0
    local bx = x + 2 + (k - 1) * bw
    r.ImGui_DrawList_AddRectFilled(dl, bx + 1, y + h - 2 - v * (h - 4), bx + bw - 1, y + h - 2,
      k == pos + 1 and C.accent or 0x7A7A7AFF, 1)
  end
end

-- the device's preset: name, and a menu to step through REAPER's presets for it
function D.preset_menu(tr, i)
  if r.ImGui_BeginPopup(ctx, "##preset") then
    local _, name = r.TrackFX_GetPreset(tr, i, "")
    local idx, n = r.TrackFX_GetPresetIndex(tr, i)
    U.text_col(C.dim, (name ~= "" and name or "No preset") .. (n and n > 0 and ("   (" .. (idx + 1) .. " / " .. n .. ")") or ""))
    r.ImGui_Separator(ctx)
    if r.ImGui_MenuItem(ctx, "Next preset") then r.TrackFX_NavigatePresets(tr, i, 1) end
    if r.ImGui_MenuItem(ctx, "Previous preset") then r.TrackFX_NavigatePresets(tr, i, -1) end
    if r.ImGui_MenuItem(ctx, "Open the plug-in window") then r.TrackFX_Show(tr, i, 3) end
    r.ImGui_EndPopup(ctx)
  end
end

function U.folder(dl, cx, cy, col)
  r.ImGui_DrawList_AddRectFilled(dl, cx - 6, cy - 4, cx - 1, cy - 2, col, 1)
  r.ImGui_DrawList_AddRectFilled(dl, cx - 6, cy - 2.5, cx + 6, cy + 5, col, 1.5)
end

-- Bitwig's Remote Controls pane: the preset row, the page chooser, then 8 controls, 4 x 2.
-- Returns the plug-in's pages and the device page on show (nil on a modulator page).
function D.remote(tr, i, guid, x, y, w, dl)
  local pl, list = RC.entries(tr, i, guid)
  local cur = RC.sel(guid, pl, list)
  local e = list[cur]
  -- the preset row
  r.ImGui_DrawList_AddRectFilled(dl, x - 3, y - 3, x + w + 3, y + 41, C.headbox, 3)
  r.ImGui_DrawList_AddRect(dl, x - 3, y - 3, x + w + 3, y + 41, C.pane_edge, 3, 0, 1)
  r.ImGui_SetCursorScreenPos(ctx, x - 3, y - 3)
  if r.ImGui_InvisibleButton(ctx, "##presetrow", w + 6, 22) then r.ImGui_OpenPopup(ctx, "##preset") end
  local prh = r.ImGui_IsItemHovered(ctx)
  U.folder(dl, x + 6, y + 6, prh and C.text or C.icon)
  local _, pname = r.TrackFX_GetPreset(tr, i, "")
  r.ImGui_DrawList_AddTextEx(dl, font_bold, 12, x + 18, y, prh and C.text or C.headtext, H.fit(pname ~= "" and pname or "init", w - 24))
  if prh then r.ImGui_SetTooltip(ctx, "Preset: next, previous") end
  -- the page chooser
  local py = y + 22
  r.ImGui_SetCursorScreenPos(ctx, x, py)
  -- a click opens the page menu - a moment later, so that a double-click can rename the page
  -- in place instead (Bitwig: double-click a name to rename it)
  local editing = S.pgedit and S.pgedit.guid == guid
  if not editing and r.ImGui_InvisibleButton(ctx, "##page", w, 20) then
    S.guid = guid
    S.pgclick = { guid = guid, t = r.time_precise() }
  end
  local phov = not editing and r.ImGui_IsItemHovered(ctx)
  if phov and r.ImGui_IsMouseDoubleClicked(ctx, 0) and e and e.kind == "p" then
    S.pgclick = nil
    S.pgedit = { guid = guid, k = e.k, buf = e.name, first = true }
    editing = true
  end
  if S.pgclick and S.pgclick.guid == guid and r.time_precise() - S.pgclick.t > 0.28 then
    S.pgclick = nil
    S.rcmenu = { guid = guid, open = true }
  end
  U.i_knob(dl, x + 8, py + 10, phov and C.text or C.icon, false)
  if editing then
    local m = S.pgedit
    r.ImGui_SetCursorScreenPos(ctx, x + 18, py)
    r.ImGui_SetNextItemWidth(ctx, w - 20)
    if m.first then r.ImGui_SetKeyboardFocusHere(ctx) end
    local ch, buf = r.ImGui_InputText(ctx, "##pgedit", m.buf)
    if ch then m.buf = buf end
    if not m.first and not r.ImGui_IsItemActive(ctx) then
      local pg = pl and pl.pages[m.k]
      local name = m.buf:gsub("^%s+", ""):gsub("%s+$", "")
      if pg and name ~= "" and name ~= pg.name then
        pg.name = name
        RC.save()
      end
      S.pgedit = nil
    end
    m.first = false
  else
    local ptxt = H.fit(e and e.name or "No pages", w - 40)
    local _, pth = r.ImGui_CalcTextSize(ctx, ptxt)
    r.ImGui_DrawList_AddTextEx(dl, font_bold, 12, x + 20, py + (20 - pth) / 2, phov and C.text or (e and C.headtext or C.dim), ptxt)
    local tw = r.ImGui_CalcTextSize(ctx, ptxt)
    r.ImGui_DrawList_AddTriangleFilled(dl, x + 24 + tw, py + 9, x + 30 + tw, py + 9, x + 27 + tw, py + 13, C.dim)
  end
  if phov then
    r.ImGui_SetTooltip(ctx, (e and ("Page " .. cur .. " of " .. #list .. "\n") or "")
      .. "Click: choose, new, learn, fill, delete" .. ((e and e.kind == "p") and "\nDouble-click: rename" or ""))
  end
  local sy = py + 26
  if not e then                             -- no pages and no modulators yet
    local t = "No remote control pages"
    local tw2 = r.ImGui_CalcTextSize(ctx, t)
    r.ImGui_DrawList_AddText(dl, x + (w - tw2) / 2, sy + 10, C.dim, t)
    local kw = math.floor((w - 12) / 2)
    r.ImGui_SetCursorScreenPos(ctx, x + 4, sy + 34)
    if U.key("newpg", "New page", false, kw, 22, "An empty page: click its slots to learn") then
      S.rcpage[guid] = RC.new_page(RC.plugin(tr, i, true))
      RC.save()
    end
    r.ImGui_SetCursorScreenPos(ctx, x + 8 + kw, sy + 34)
    if U.key("autopg", "Auto pages", false, kw, 22, "Pages from the plug-in's parameter groups (VCF1:, Osc ...),\nor else one page with the first 8 parameters") then
      if RC.autopages(tr, i, guid) == 0 then RC.fill(tr, i, guid, 1) end
      S.rcpage[guid], S.rcmod[guid] = 1, nil
    end
    return pl, nil
  end
  if e.kind == "m" then
    D.modpage(tr, e.lg, x, sy, w, dl)
    return pl, nil
  end
  local mods = S.mods[guid] or {}
  local sx = x + (w - 4 * SLOT) / 2
  for k = 1, 8 do
    D.slot(tr, i, guid, pl, e.k, k, sx + ((k - 1) % 4) * SLOT, sy + ((k - 1) // 4) * (SH + 2), mods, dl)
  end
  return pl, e.k
end

-- the slot and page menus of one device (inside its PushID)
function D.card_menus(tr, i, guid, pl, page)
  local m = S.rcmenu
  if m and m.open and m.guid == guid then
    m.open = false
    r.ImGui_OpenPopup(ctx, m.slot and "##slotmenu" or "##pagemenu")
  end
  if r.ImGui_BeginPopup(ctx, "##slotmenu") then
    if m and m.guid == guid and m.slot then
      local pg = pl and pl.pages[m.page]
      local slot = pg and pg.slots[m.slot]
      U.text_col(C.dim, slot and slot.n or ("Slot " .. m.slot))
      r.ImGui_Separator(ctx)
      if r.ImGui_MenuItem(ctx, "Learn") then
        local pl2 = RC.plugin(tr, i, true)
        if #pl2.pages == 0 then RC.new_page(pl2); RC.save() end
        RC.learn(guid, m.page, m.slot)
      end
      if slot and r.ImGui_MenuItem(ctx, "Clear") then pg.slots[m.slot] = false; RC.save() end
      if slot and m.p then
        if r.ImGui_MenuItem(ctx, "Show in the parameter list") then
          S.guid, S.q[guid], S.vl[guid] = guid, slot.n, true
        end
        r.ImGui_Separator(ctx)
        M.menu_items(tr, guid, m.p, (S.mods[guid] or {})[m.p])
      end
    end
    r.ImGui_EndPopup(ctx)
  end
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), 0x1E1E1EFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), 0x3A3A3AFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), 0x2E2E2EFF)
  local menu_open = r.ImGui_BeginPopup(ctx, "##pagemenu")
  r.ImGui_PopStyleColor(ctx, 3)
  if menu_open then
    local _, list = RC.entries(tr, i, guid)
    local cur = RC.sel(guid, pl, list)
    local pdl = r.ImGui_GetWindowDrawList(ctx)
    local function head(t)
      r.ImGui_PushFont(ctx, font_bold, 11)
      U.text_col(C.accent, t)
      r.ImGui_PopFont(ctx)
    end
    local function item(id, label, selected)
      local x0, y0 = r.ImGui_GetCursorScreenPos(ctx)
      local hit = r.ImGui_Selectable(ctx, "      " .. label .. id, selected, 0, 210, 0)
      U.i_remote(pdl, x0 + 8, y0 + 8, C.label, true)
      return hit
    end
    -- the plug-in's pages
    head("DEVICE PAGES")
    local ax, ay = r.ImGui_GetCursorScreenPos(ctx)
    if r.ImGui_Selectable(ctx, "  +   Add New Page##addpg", false, 0, 210, 0) then
      local pl2 = RC.plugin(tr, i, true)
      S.rcpage[guid] = RC.new_page(pl2)
      S.rcmod[guid] = nil
      RC.save()
    end
    r.ImGui_DrawList_AddRectFilled(pdl, ax - 2, ay - 1, ax + 212, ay + 17, 0xFFFFFF12, 3)
    for n, e in ipairs(list) do
      if e.kind == "p" and item("##e" .. n, e.name, n == cur) then RC.go(guid, e) end
    end
    -- the modulators' pages
    local any
    for n, e in ipairs(list) do
      if e.kind == "m" then
        if not any then head("MODULATOR PAGES"); any = true end
        if item("##e" .. n, e.name, n == cur) then RC.go(guid, e) end
      end
    end
    r.ImGui_Separator(ctx)
    local pg = pl and page and pl.pages[page]
    if pg then
      r.ImGui_SetNextItemWidth(ctx, 210)
      local changed, name = r.ImGui_InputTextWithHint(ctx, "##pgname", "Page name", pg.name)
      if changed then pg.name = name end
      if r.ImGui_IsItemDeactivatedAfterEdit(ctx) then RC.save() end
    end
    if r.ImGui_MenuItem(ctx, "Learn this page") then
      local pl2 = RC.plugin(tr, i, true)
      if #pl2.pages == 0 then RC.new_page(pl2); RC.save() end
      local k0 = 1
      for k = 1, 8 do
        if not pl2.pages[RC.cur(guid, pl2)].slots[k] then k0 = k; break end
      end
      S.rcmod[guid] = nil
      RC.learn(guid, RC.cur(guid, pl2), k0)
    end
    if r.ImGui_MenuItem(ctx, "Make pages from groups") then
      local before = #(RC.plugin(tr, i, true).pages)
      if RC.autopages(tr, i, guid) > 0 then S.rcpage[guid], S.rcmod[guid] = before + 1, nil
      else H.say("no parameter groups found in this plug-in") end
    end
    if r.ImGui_MenuItem(ctx, "Fill with the next 8 parameters") then
      RC.fill(tr, i, guid, page or RC.cur(guid, RC.plugin(tr, i, true)))
      S.rcmod[guid] = nil
    end
    if pg and r.ImGui_MenuItem(ctx, "Clear this page") then
      for k = 1, 8 do pg.slots[k] = false end
      RC.save()
    end
    if pg and r.ImGui_MenuItem(ctx, "Delete this page") then
      table.remove(pl.pages, page)
      if #pl.pages == 0 then RC.data.plugins[RC.key(tr, i)] = nil end
      RC.save()
    end
    r.ImGui_EndPopup(ctx)
  end
end

---------------------------------------------------------------- the parameter list in a device
-- Bitwig's plug-in device (user guide, Plug-ins chapter): ONE list with every parameter, a
-- search field whose magnifier is a menu (only automated and modulated parameters; recent
-- searches), and above the list a single knob that follows the last touched parameter.
function D.filtered(guid, c, q)
  local only = S.fmod[guid] and true or false
  local key = c.n .. "|" .. q .. "|" .. tostring(only) .. "|" .. S.scan_count .. "|" .. tostring(S.pinmod)
  local hit = S.filt[guid]
  if hit and hit.key == key then return hit.list, hit.npin end
  local out, pinned = {}, {}
  local mods, aut = S.mods[guid] or {}, S.auto[guid] or {}
  local pin = S.pinmod and q == "" and not only
  q = q:lower()
  for _, e in ipairs(c.list) do
    if (q == "" or e[3]:find(q, 1, true)) and (not only or mods[e[1]] or aut[e[1]]) then
      if pin and mods[e[1]] then pinned[#pinned + 1] = e else out[#out + 1] = e end
    end
  end
  -- the modulated ones first (the line under them is drawn by the list)
  for k = #pinned, 1, -1 do table.insert(out, 1, pinned[k]) end
  S.filt[guid] = { key = key, list = out, npin = #pinned }
  return out, #pinned
end

-- a drag on a parameter: its value (the base when modulated), or - while the routing button
-- of an LFO that drives it is on - the modulation amount (Bitwig: click the target, drag)
function D.drag(tr, i, p, base, cur, modded, label)
  local _, dy = r.ImGui_GetMouseDelta(ctx)
  if dy == 0 then return base, cur end
  local k = dy / 160 * (H.mods() and 0.1 or 1)
  local li = S.route and F.index(tr, S.route)
  if li and (F.cfg(tr, i, p, "plink.active") or 0) ~= 0 and F.cfg(tr, i, p, "plink.effect") == li
    and F.cfg(tr, i, p, "plink.param") == (S.route_out or F.param_index_cached(tr, li)) then
    F.set(tr, i, p, "plink.scale", H.clamp((F.cfg(tr, i, p, "plink.scale") or 0) - 2 * k, -2, 2))
    S.drag = "modulation amount"
    return base, cur
  end
  local nv = H.clamp(base - k, 0, 1)
  if modded then F.base_set(tr, i, p, nv) else r.TrackFX_SetParamNormalized(tr, i, p, nv) end
  S.drag = label
  return nv, modded and cur or nv
end
-- a click on a parameter while a routing button is on: route that LFO to it (amount 0, the
-- drag sets it). Returns true when it was a routing click.
function D.route_hit(tr, i, p)
  local src = S.route_src
  if src and not S.route and src.track ~= r.GetTrackGUID(tr) then   -- a modulator on another track
    local rg = M.route_global(src, tr, i, p)
    if rg then S.route, S.route_out = rg, nil end
    return true
  end
  if not S.route then return false end
  local li = F.index(tr, S.route)
  if not li then S.route = nil; return false end
  if li == i then return true end
  local tg = r.TrackFX_GetFXGUID(tr, i)
  for _, rt in ipairs(S.routes[tg] or {}) do         -- the target modulates this modulator: a loop
    if rt.tgt == S.route then return true end
  end
  local out = S.route_out or F.param_index_cached(tr, li)
  local same = (F.cfg(tr, i, p, "plink.active") or 0) ~= 0 and F.cfg(tr, i, p, "plink.effect") == li
    and F.cfg(tr, i, p, "plink.param") == out
  if not same then M.route(tr, li, i, p, 0, nil, out) end
  return true
end

-- one parameter row: a knob, the name in white, the value in grey; act = being dragged
function D.prow(tr, i, guid, p, name, x, y, w, hov, act, dl)
  local modded = (S.mods[guid] or {})[p]
  local cur = r.TrackFX_GetParamNormalized(tr, i, p)
  local base = modded and (F.base_get(tr, i, p) or cur) or cur
  S.txtc[guid] = S.txtc[guid] or {}
  local tc = S.txtc[guid][p]
  if not tc or tc[1] ~= cur then
    tc = { cur, (select(2, r.TrackFX_GetFormattedParamValue(tr, i, p, ""))) }
    S.txtc[guid][p] = tc
  end
  if act then
    base, cur = D.drag(tr, i, p, base, cur, modded, name)
    if S.drag then M.set_joker(tr, guid, p) end
  end
  if hov or act then r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + ROW - 1, C.hover) end
  r.ImGui_DrawList_AddLine(dl, x, y + ROW - 0.5, x + w, y + ROW - 0.5, C.pane_edge, 1)
  U.knob(dl, x + 16, y + ROW / 2, 11, base, cur, modded, hov, D.span(modded, tr, i, p, base))
  r.ImGui_DrawList_AddTextEx(dl, font_bold, 12, x + 33, y + 2, modded and C.mod or C.text, H.fit(name, w - 38))
  r.ImGui_DrawList_AddText(dl, x + 33, y + 16, act and C.value or C.label, H.fit(tc[2], w - 38))
  if hov then r.ImGui_SetTooltip(ctx, name .. "\n" .. tc[2] .. (modded and "\n(modulated)" or "")) end
end

-- the joker's parameter per FX, kept in the track (P_EXT) so it is still there after reopening
function M.get_joker(tr, guid)
  local p = S.joker[guid]
  if p == nil then
    local _, v = r.GetSetMediaTrackInfo_String(tr, "P_EXT:TKBIT_JOKER_" .. (guid:gsub("[{}]", "")), "", false)
    p = tonumber(v) or false
    S.joker[guid] = p
  end
  return p or nil
end
function M.set_joker(tr, guid, p)
  if S.joker[guid] == p then return end
  S.joker[guid] = p
  r.GetSetMediaTrackInfo_String(tr, "P_EXT:TKBIT_JOKER_" .. (guid:gsub("[{}]", "")), tostring(p), true)
end

-- the knob above the list: the last parameter touched on this device (in its window or here)
function D.joker(tr, i, guid, x, y, w, dl)
  local c = F.params(tr, i, guid)
  local p = M.get_joker(tr, guid)
  if not p or p >= c.n then                   -- nothing touched yet: the first modulated one
    p = 0
    local mods = S.mods[guid] or {}
    for _, e in ipairs(c.list) do
      if mods[e[1]] then p = e[1]; break end
    end
  end
  local e = c.list[p + 1]
  if not e then return end
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  r.ImGui_InvisibleButton(ctx, "##joker", w, ROW)
  local hov, act = r.ImGui_IsItemHovered(ctx), r.ImGui_IsItemActive(ctx)
  if r.ImGui_IsItemActivated(ctx) then
    S.guid = guid
    if not D.route_hit(tr, i, p) and S.learn and S.learn.guid == guid then RC.learned(tr, i, p) end
  end
  if r.ImGui_IsItemDeactivated(ctx) and S.drag then
    r.Undo_OnStateChangeEx2(0, "Devices: " .. S.drag, 2, -1)
    S.drag = nil
  end
  if r.ImGui_IsItemClicked(ctx, 1) then
    S.menu_p = { fx = guid, p = p, name = e[2], modded = (S.mods[guid] or {})[p], open = true }
  end
  D.prow(tr, i, guid, p, e[2], x, y, w, hov and not act, act and not (S.learn and S.learn.guid == guid), dl)
end

-- GetTouchedOrFocusedFX feeds the joker of the device that was touched (on this track)
function D.touch_poll(tr)
  local snap = RC.snap()
  if snap == S.touch_snap then return end
  S.touch_snap = snap
  local ti, ii, fx, pa = RC.touch()
  local my = tr == r.GetMasterTrack(0) and -1 or math.floor(r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")) - 1
  if ti == my and ii == -1 and fx and pa and fx < r.TrackFX_GetCount(tr) then
    M.set_joker(tr, r.TrackFX_GetFXGUID(tr, fx), pa)
  end
end

-- the scrolling list; one hit area for the visible rows (a button per row costs ~8 calls)
function D.list(tr, i, guid, x, y, w, h)
  if h < ROW then return end
  local c = F.params(tr, i, guid)
  local list, npin = D.filtered(guid, c, S.q[guid] or "")
  local mods = S.mods[guid] or {}
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  if not r.ImGui_BeginChild(ctx, "##list", w, h, 0, 0) then return end
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x0, y0 = r.ImGui_GetCursorScreenPos(ctx)
  local cw = r.ImGui_GetContentRegionAvail(ctx)
  local _, wy = r.ImGui_GetWindowPos(ctx)
  local first = math.max(0, math.floor((wy - y0) / ROW))
  local last = math.min(#list - 1, math.floor((wy + h - y0) / ROW))
  local hk, active_k
  if last >= first then
    r.ImGui_SetCursorScreenPos(ctx, x0, y0 + first * ROW)
    r.ImGui_InvisibleButton(ctx, "##rows", math.max(1, cw), (last - first + 1) * ROW)
    if r.ImGui_IsItemHovered(ctx) or r.ImGui_IsItemActivated(ctx) then
      local _, my = r.ImGui_GetMousePos(ctx)
      hk = math.floor((my - y0) / ROW) + 1
      if not list[hk] then hk = nil end
    end
    if r.ImGui_IsItemActivated(ctx) then
      -- the drag follows the PARAMETER, not the row: with modulated parameters on top, a
      -- routing click moves the row to the top under the mouse
      S.drag_k = hk and { guid = guid, p = list[hk][1] } or nil
      S.guid = guid
      if hk then M.set_joker(tr, guid, list[hk][1]) end
      if hk and D.route_hit(tr, i, list[hk][1]) then
        -- routing: the drag that follows sets the amount
      elseif hk and S.learn and S.learn.guid == guid then      -- a remote slot is learning: assign
        RC.learned(tr, i, list[hk][1])
        S.drag_k = nil
      end
    end
    if r.ImGui_IsItemActive(ctx) and S.drag_k and S.drag_k.guid == guid then
      for k, e in ipairs(list) do
        if e[1] == S.drag_k.p then active_k = k; break end
      end
      if active_k and (active_k < first + 1 or active_k > last + 1) then   -- scrolled out of view: drag it anyway
        local e = list[active_k]
        local modded = mods[e[1]]
        local cur = r.TrackFX_GetParamNormalized(tr, i, e[1])
        D.drag(tr, i, e[1], modded and (F.base_get(tr, i, e[1]) or cur) or cur, cur, modded, e[2])
      end
    end
    if r.ImGui_IsItemDeactivated(ctx) then
      if S.drag then r.Undo_OnStateChangeEx2(0, "Devices: " .. S.drag, 2, -1) end
      S.drag, S.drag_k = nil, nil
    end
    if hk and r.ImGui_IsItemClicked(ctx, 1) then
      local e = list[hk]
      S.menu_p = { fx = guid, p = e[1], name = e[2], modded = mods[e[1]], open = true }
    end
    if active_k then hk = nil end
  end
  for k = first + 1, last + 1 do
    local e = list[k]
    D.prow(tr, i, guid, e[1], e[2], x0, y0 + (k - 1) * ROW, cw, k == hk, k == active_k, dl)
    if npin and npin > 0 and k == npin and npin < #list then   -- the end of the modulated ones
      r.ImGui_DrawList_AddLine(dl, x0, y0 + k * ROW - 1, x0 + cw, y0 + k * ROW - 1, C.mod_dim, 2)
    end
  end
  if #list == 0 then
    r.ImGui_DrawList_AddText(dl, x0 + 8, y0 + 8, C.dim, S.fmod[guid] and "No automated or modulated parameters" or "No match")
  end
  r.ImGui_SetCursorScreenPos(ctx, x0, y0 + #list * ROW)
  r.ImGui_Dummy(ctx, 1, 0)
  r.ImGui_EndChild(ctx)
end

-- the parameter menu (the list's and the joker's), in the device's ID scope
function D.param_menu(tr, i, guid)
  local m = S.menu_p
  if m and m.open and m.fx == guid then m.open = false; r.ImGui_OpenPopup(ctx, "##pmenu") end
  if r.ImGui_BeginPopup(ctx, "##pmenu") then
    if m and m.fx == guid then
      U.text_col(C.dim, m.name)
      r.ImGui_Separator(ctx)
      if r.ImGui_MenuItem(ctx, "Add to remote controls") then RC.add(tr, i, guid, m.p); S.vr[guid] = true end
      r.ImGui_Separator(ctx)
      M.menu_items(tr, guid, m.p, m.modded)
    end
    r.ImGui_EndPopup(ctx)
  end
end

-- the search field; its magnifier opens the filter and the recent searches
function D.search(guid, x, y, w, dl)
  local q = S.q[guid] or ""
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  r.ImGui_SetNextItemWidth(ctx, w)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 24, 2)
  local changed, nq = r.ImGui_InputText(ctx, "##q", q)
  r.ImGui_PopStyleVar(ctx)
  if changed then S.q[guid] = nq; q = nq end
  if r.ImGui_IsItemDeactivated(ctx) and q ~= "" then
    for k = #S.hist, 1, -1 do if S.hist[k] == q then table.remove(S.hist, k) end end
    table.insert(S.hist, 1, q)
    S.hist[9] = nil
  end
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  if r.ImGui_InvisibleButton(ctx, "##qmenu", 22, 18) then r.ImGui_OpenPopup(ctx, "##qpop") end
  local mh = r.ImGui_IsItemHovered(ctx)
  local mc = S.fmod[guid] and C.accent or (mh and C.text or C.icon)
  r.ImGui_DrawList_AddCircle(dl, x + 8, y + 8, 3.5, mc, 12, 1.3)
  r.ImGui_DrawList_AddLine(dl, x + 10.5, y + 10.5, x + 13, y + 13, mc, 1.3)
  r.ImGui_DrawList_AddTriangleFilled(dl, x + 15, y + 10, x + 20, y + 10, x + 17.5, y + 13, mc)
  if mh then r.ImGui_SetTooltip(ctx, "Filter and recent searches") end
  if r.ImGui_BeginPopup(ctx, "##qpop") then
    if r.ImGui_MenuItem(ctx, "Show only automated and modulated parameters", nil, S.fmod[guid] == true) then
      S.fmod[guid] = not S.fmod[guid]
    end
    if r.ImGui_MenuItem(ctx, "Modulated parameters on top", nil, S.pinmod) then
      S.pinmod = not S.pinmod
      r.SetExtState("TK Bit Devices", "pin_mod", S.pinmod and "1" or "0", true)
    end
    if #S.hist > 0 then
      r.ImGui_Separator(ctx)
      U.text_col(C.dim, "SEARCH HISTORY")
      for k, h in ipairs(S.hist) do
        if r.ImGui_MenuItem(ctx, h .. "##h" .. k) then S.q[guid] = h end
      end
    end
    r.ImGui_EndPopup(ctx)
  end
  if q ~= "" then
    r.ImGui_SetCursorScreenPos(ctx, x + w - 16, y)
    if r.ImGui_InvisibleButton(ctx, "##qx", 16, 18) then S.q[guid] = "" end
    local xc = r.ImGui_IsItemHovered(ctx) and C.text or C.icon
    r.ImGui_DrawList_AddLine(dl, x + w - 11, y + 5, x + w - 5, y + 11, xc, 1.4)
    r.ImGui_DrawList_AddLine(dl, x + w - 5, y + 5, x + w - 11, y + 11, xc, 1.4)
  end
end

---------------------------------------------------------------- a device
function U.i_remote(dl, cx, cy, col, on)        -- a dial: Bitwig's remote controls button
  if on then r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, 6.5, col, 16) end
  r.ImGui_DrawList_AddCircle(dl, cx, cy, 6, on and 0x141414FF or col, 16, 1.4)
  r.ImGui_DrawList_AddLine(dl, cx, cy, cx + 2.5, cy - 4, on and 0x141414FF or col, 1.6)
end
function U.i_mod(dl, cx, cy, col)             -- a modulation arrow
  r.ImGui_DrawList_AddCircle(dl, cx - 3, cy, 2.5, col, 8, 1.2)
  r.ImGui_DrawList_AddLine(dl, cx - 0.5, cy, cx + 5, cy, col, 1.2)
  r.ImGui_DrawList_AddTriangleFilled(dl, cx + 6, cy, cx + 3, cy - 2.5, cx + 3, cy + 2.5, col)
end
-- a strip icon key; returns clicked
function D.sicon(id, x, y, icon, on, tip, dl)
  r.ImGui_SetCursorScreenPos(ctx, x + 2, y)
  local hit = r.ImGui_InvisibleButton(ctx, id, STRIP - 4, 18)
  local hov = r.ImGui_IsItemHovered(ctx)
  if hov then r.ImGui_SetTooltip(ctx, tip) end
  icon(dl, x + STRIP / 2, y + 9, on and C.accent or (hov and C.text or C.icon), on)
  return hit
end

local LW = 176                     -- the parameter list's width
local MPW = 74                     -- the modulators pane's width

-- one LFO tile, as Bitwig's: the curve and the routing button. Click: its controls (the remote
-- controls pane on its page); right-click: more.
-- the output of the last ~2 s (Random, Follower), kept per modulator
S.mh = {}
function M.history(lg, v)
  local h = S.mh[lg]
  if not h then h = { i = 0 }; S.mh[lg] = h end
  h.i = h.i % 64 + 1
  h[h.i] = v
  return h
end

---------------------------------------------------------------- the modulator editors (">")
-- what is not on Bitwig's panel but our JSFX has: under the "..." in the editor's head
local EXTRA = {
  adsr = { { "knob", "Velocity", "Velocity" }, { "choose", "Single", "Single trigger", { "Off", "On" } },
    { "knob", "Amount", "Amount" }, { "bip" } },
  midi = { { "knob", "Smooth", "Smooth" }, { "knob", "Amount", "Amount" }, { "bip" } },
  macro4 = { { "bip" } },
  keytrack = { { "knob", "Glide", "Glide" }, { "knob", "Amount", "Amount" } },
  button = { { "choose", "Mode", "Mode", { "Toggle", "Momentary" } }, { "knob", "Smooth", "Smooth" },
    { "knob", "Amount", "Amount" }, { "bip" } },
  buttons = { { "choose", "Mode", "Mode", { "Toggle", "Momentary" } }, { "bip" } },
}
local EXW = { adsr = 4 * SLOT + 18, midi = 196, macro4 = 78 }   -- the editor's width (else 4 x SLOT)

-- extra settings as plain controls (in a popup)
function D.extra_items(tr, li, lg, list)
  for _, it in ipairs(list) do
    if it[1] == "bip" then
      local bip = M.bipolar(tr, li)
      local ch, nv = r.ImGui_Checkbox(ctx, "Bipolar", bip)
      if ch then M.set_bipolar(tr, lg, nv) end
    else
      local p = F.param_index_c(tr, li, it[2])
      if p and it[1] == "knob" then
        local v = r.TrackFX_GetParamNormalized(tr, li, p)
        local _, txt = r.TrackFX_GetFormattedParamValue(tr, li, p, "")
        r.ImGui_SetNextItemWidth(ctx, 140)
        local ch, nv = r.ImGui_SliderDouble(ctx, it[3] .. "##x" .. p, v, 0, 1, txt:gsub("%%", "%%%%"))
        if ch then r.TrackFX_SetParamNormalized(tr, li, p, nv) end
        if r.ImGui_IsItemDeactivatedAfterEdit(ctx) then r.Undo_OnStateChangeEx2(0, "Devices: " .. it[3], 2, -1) end
      elseif p and it[1] == "choose" then
        local cur = math.floor(r.TrackFX_GetParam(tr, li, p) + 0.5)
        U.text_col(C.dim, it[3])
        for k, nm in ipairs(it[4]) do
          if r.ImGui_MenuItem(ctx, "  " .. nm .. "##c" .. p .. k, nil, cur == k - 1) then r.TrackFX_SetParam(tr, li, p, k - 1) end
        end
      end
    end
  end
end

-- the unfolded editor of modulator lg: its name on top ("..." = the extra settings), then its
-- own layout (ADSR, MIDI, Macro-4) or its controls as on a remote page
function D.mexp(tr, li, lg, kind, x, y, w, h, dl)
  r.ImGui_PushID(ctx, "mexp" .. lg)
  local title = MODS[kind].label
  local tw = r.ImGui_CalcTextSize(ctx, title)
  r.ImGui_DrawList_AddTextEx(dl, font_bold, 12, x + (w - tw) / 2, y + 3, C.accent, title)
  if EXTRA[kind] then
    r.ImGui_SetCursorScreenPos(ctx, x + w - 20, y + 2)
    if r.ImGui_InvisibleButton(ctx, "##more", 18, 14) then r.ImGui_OpenPopup(ctx, "##extra") end
    local mh = r.ImGui_IsItemHovered(ctx)
    for k = -1, 1 do r.ImGui_DrawList_AddCircleFilled(dl, x + w - 11 + k * 4, y + 9, 1.4, mh and C.text or C.dim, 6) end
    if mh then r.ImGui_SetTooltip(ctx, "More settings") end
    if r.ImGui_BeginPopup(ctx, "##extra") then
      D.extra_items(tr, li, lg, EXTRA[kind])
      r.ImGui_EndPopup(ctx)
    end
  end
  local by = y + 20
  if kind == "adsr" then
    D.adsr_editor(tr, li, x, by, w, h - 20, dl)
  elseif kind == "midi" then
    D.midi_editor(tr, li, x, by, w, h - 20, dl)
  elseif kind == "macro4" then
    D.macro4_editor(tr, li, lg, x, by, w, h - 20, dl)
  else
    r.ImGui_PushFont(ctx, font, 12)
    D.modpage(tr, lg, x + 4, by + 2, w - 8, dl)
    r.ImGui_PopFont(ctx)
    if kind == "follower" then D.follower_meter(tr, li, x + 8, y + h - 18, w - 16, dl) end
  end
  r.ImGui_PopID(ctx)
end

-- the Follower's input: what it hears, -60..0 dB, with the number (no sound = it stays at 0)
function D.follower_meter(tr, li, x, y, w, dl)
  local lp = F.param_index_c(tr, li, "Level (dB)")
  if not lp then
    r.ImGui_DrawList_AddText(dl, x, y, C.dim, "(reopen the project for the input meter)")
    return
  end
  local db = r.TrackFX_GetParam(tr, li, lp)
  local t = H.clamp((db + 60) / 60, 0, 1)
  local mx = x + 44
  r.ImGui_DrawList_AddText(dl, x, y, C.label, "Input")
  r.ImGui_DrawList_AddRectFilled(dl, mx, y + 3, x + w - 52, y + 11, C.headbox, 2)
  r.ImGui_DrawList_AddRectFilled(dl, mx, y + 3, mx + (x + w - 52 - mx) * t, y + 11, t > 0.95 and C.bad or C.mod, 2)
  local txt = db <= -119 and "silence" or ("%.1f dB"):format(db)
  local tw = r.ImGui_CalcTextSize(ctx, txt)
  r.ImGui_DrawList_AddText(dl, x + w - tw, y, db <= -119 and C.bad or C.text, txt)
end

-- ADSR: the envelope as a graph with A, D, S and R to drag (times on a square-root scale), the
-- output as a meter, and the four knobs under it (as Bitwig's)
function D.adsr_editor(tr, li, x, y, w, h, dl)
  local function P(n) return F.param_index_c(tr, li, n) end
  local pa, pd, ps, pr = P("Attack (ms)"), P("Decay (ms)"), P("Sustain"), P("Release (ms)")
  if not (pa and pd and ps and pr) then return end
  local gx, gy, gw, gh = x + 6, y, w - 26, h - SH - 6
  r.ImGui_DrawList_AddRectFilled(dl, gx, gy, gx + gw, gy + gh, C.headbox, 3)
  for k = 1, 5 do r.ImGui_DrawList_AddLine(dl, gx + k * gw / 6, gy, gx + k * gw / 6, gy + gh, C.grid, 1) end
  for k = 1, 3 do r.ImGui_DrawList_AddLine(dl, gx, gy + k * gh / 4, gx + gw, gy + k * gh / 4, C.grid, 1) end
  -- everything in REAPER's normalized 0..1, as the knobs: the points wrote milliseconds with
  -- TrackFX_SetParam to the JSFX's log sliders, and dragging a point crashed REAPER (2026-11-26)
  local seg, hold = math.max(10, gw * 0.27), gw * 0.19
  local na, nd, su, nr = r.TrackFX_GetParamNormalized(tr, li, pa), r.TrackFX_GetParamNormalized(tr, li, pd),
    r.TrackFX_GetParamNormalized(tr, li, ps), r.TrackFX_GetParamNormalized(tr, li, pr)
  local yt, yb = gy + 10, math.max(gy + 20, gy + gh - 8)
  local xA = gx + na * seg
  local xD = xA + nd * seg
  local ys = yb - su * (yb - yt)
  local xS = xD + hold
  local xR = xS + nr * seg
  r.ImGui_DrawList_PathLineTo(dl, gx, yb)
  r.ImGui_DrawList_PathLineTo(dl, xA, yt)
  r.ImGui_DrawList_PathLineTo(dl, xD, ys)
  r.ImGui_DrawList_PathLineTo(dl, xS, ys)
  r.ImGui_DrawList_PathLineTo(dl, xR, yb)
  r.ImGui_DrawList_PathStroke(dl, C.env, 0, 2)
  -- the handles
  local function handle(id, hx, hy, letter, fn)
    r.ImGui_SetCursorScreenPos(ctx, hx - 8, hy - 8)
    r.ImGui_InvisibleButton(ctx, id, 16, 16)
    local hov, act = r.ImGui_IsItemHovered(ctx), r.ImGui_IsItemActive(ctx)
    if act then
      S.drag = "ADSR"                         -- (no modulation scan while dragging)
      local dx, dy = r.ImGui_GetMouseDelta(ctx)
      if dx ~= 0 or dy ~= 0 then fn(dx * (H.mods() and 0.1 or 1), dy * (H.mods() and 0.1 or 1)) end
    end
    if r.ImGui_IsItemDeactivated(ctx) then
      S.drag = nil
      r.Undo_OnStateChangeEx2(0, "Devices: ADSR", 2, -1)
    end
    r.ImGui_DrawList_AddCircleFilled(dl, hx, hy, (hov or act) and 7.5 or 6.5, C.env, 16)
    local tw2, th2 = r.ImGui_CalcTextSize(ctx, letter)
    r.ImGui_DrawList_AddTextEx(dl, font_bold, 11, hx - tw2 / 2 + 0.5, hy - th2 / 2 + 1, C.env_text, letter)
    if hov and not act then r.ImGui_SetTooltip(ctx, select(2, r.TrackFX_GetFormattedParamValue(tr, li,
      ({ A = pa, D = pd, S = ps, R = pr })[letter], ""))) end
  end
  local function put(p, v)                    -- a real, finite change only, normalized
    if v ~= v or v == math.huge or v == -math.huge then return end
    v = H.clamp(v, 0, 1)
    if math.abs(r.TrackFX_GetParamNormalized(tr, li, p) - v) > 1e-5 then r.TrackFX_SetParamNormalized(tr, li, p, v) end
  end
  local span = math.max(1, yb - yt)
  handle("##hA", xA, yt, "A", function(dx) put(pa, na + dx / seg) end)
  handle("##hD", xD, ys, "D", function(dx, dy)
    put(pd, nd + dx / seg)
    put(ps, su - dy / span)
  end)
  handle("##hS", xS, ys, "S", function(_, dy) put(ps, su - dy / span) end)
  handle("##hR", xR, yb, "R", function(dx) put(pr, nr + dx / seg) end)
  -- the output, as a meter
  local out = F.param_index_cached(tr, li)
  local v = r.TrackFX_GetParamNormalized(tr, li, out)
  local mx = gx + gw + 6
  r.ImGui_DrawList_AddRectFilled(dl, mx, gy, mx + 8, gy + gh, C.headbox, 2)
  r.ImGui_DrawList_AddRectFilled(dl, mx + 1, gy + gh - v * gh, mx + 7, gy + gh, C.meter, 1)
  r.ImGui_DrawList_AddRectFilled(dl, mx + 1, gy + gh - v * gh, mx + 7, gy + gh - v * gh + 2, C.accent)
  -- the knobs
  local kx = x + (w - 4 * SLOT) / 2
  local ky = y + h - SH
  D.mknob(tr, li, pa, "A", kx, ky, dl)
  D.mknob(tr, li, pd, "D", kx + SLOT, ky, dl)
  D.mknob(tr, li, ps, "S", kx + 2 * SLOT, ky, dl)
  D.mknob(tr, li, pr, "R", kx + 3 * SLOT, ky, dl)
end

-- MIDI: Message (CC / PRESSURE / BEND / VELOCITY), Controller (drag the number, or Learn CC),
-- Channel (All, or one), as Bitwig's
function D.midi_editor(tr, li, x, y, w, h, dl)
  local function P(n) return F.param_index_c(tr, li, n) end
  local pt, pc, pch, pl = P("Type"), P("CC"), P("Channel"), P("Learn")
  if not (pt and pc and pch) then return end
  local lx, vx = x + 8, x + 86
  local function label(t, ly) r.ImGui_DrawList_AddText(dl, lx, ly, C.label, t) end
  -- Message
  label("Message", y + 2)
  local cxm, cym = lx + 16, y + 34                   -- a MIDI socket
  r.ImGui_DrawList_AddCircle(dl, cxm, cym, 9, C.label, 20, 1.4)
  for k = 0, 4 do
    local an = math.pi * (0.95 + k * 0.275)
    r.ImGui_DrawList_AddCircleFilled(dl, cxm + math.cos(an) * 5, cym - math.sin(an) * 5 * -1, 1.2, C.label, 6)
  end
  local t = math.floor(r.TrackFX_GetParam(tr, li, pt) + 0.5)
  local opts = { { 0, "CC" }, { 2, "PRESSURE" }, { 1, "BEND" }, { 3, "VELOCITY" } }
  for n, o in ipairs(opts) do
    local oy = y + 2 + (n - 1) * 15
    local ow = r.ImGui_CalcTextSize(ctx, o[2])
    r.ImGui_SetCursorScreenPos(ctx, vx, oy)
    if r.ImGui_InvisibleButton(ctx, "##msg" .. n, math.max(1, w - (vx - x) - 6), 14) then
      r.TrackFX_SetParam(tr, li, pt, o[1])
      r.Undo_OnStateChangeEx2(0, "Devices: MIDI message", 2, -1)
    end
    local hov = r.ImGui_IsItemHovered(ctx)
    local on = t == o[1]
    local cx = vx + (w - (vx - x) - 6 - ow) / 2
    r.ImGui_DrawList_AddText(dl, cx, oy, on and C.accent or (hov and C.text or C.label), o[2])
    if on then r.ImGui_DrawList_AddLine(dl, cx, oy + 14, cx + ow, oy + 14, C.accent, 1) end
  end
  -- Controller
  local cyy = y + 68
  label("Controller", cyy)
  local cc = math.floor(r.TrackFX_GetParam(tr, li, pc) + 0.5)
  local learning = pl and r.TrackFX_GetParam(tr, li, pl) >= 0.5
  local ctext = learning and "..." or ("CC" .. cc)
  local ctw = r.ImGui_CalcTextSize(ctx, ctext)
  r.ImGui_SetCursorScreenPos(ctx, vx, cyy)
  r.ImGui_InvisibleButton(ctx, "##ccnum", math.max(1, w - (vx - x) - 6), 15)
  if r.ImGui_IsItemActive(ctx) then
    local _, dy = r.ImGui_GetMouseDelta(ctx)
    if dy ~= 0 then
      S.ccacc = (S.ccacc or 0) - dy / 4
      local step = S.ccacc >= 1 and math.floor(S.ccacc) or (S.ccacc <= -1 and -math.floor(-S.ccacc) or 0)
      if step ~= 0 then
        S.ccacc = S.ccacc - step
        r.TrackFX_SetParam(tr, li, pc, H.clamp(cc + step, 0, 127))
      end
    end
  end
  if r.ImGui_IsItemDeactivated(ctx) then S.ccacc = 0; r.Undo_OnStateChangeEx2(0, "Devices: MIDI controller", 2, -1) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Drag up or down for the controller number") end
  r.ImGui_DrawList_AddText(dl, vx + (w - (vx - x) - 6 - ctw) / 2, cyy, t == 0 and C.accent or C.dim, ctext)
  if pl then
    r.ImGui_SetCursorScreenPos(ctx, vx, cyy + 20)
    if U.key("learncc", "Learn CC", learning, w - (vx - x) - 6, 22, "The next CC that comes in becomes the controller") then
      r.TrackFX_SetParam(tr, li, pl, learning and 0 or 1)
    end
  end
  -- Channel
  local chy = y + 124
  label("Channel", chy + 3)
  local chan = math.floor(r.TrackFX_GetParam(tr, li, pch) + 0.5)
  local bw = (w - (vx - x) - 10) / 2
  r.ImGui_SetCursorScreenPos(ctx, vx, chy)
  if U.key("chall", "All", chan == 0, bw, 20, "Every channel") then r.TrackFX_SetParam(tr, li, pch, 0) end
  r.ImGui_SetCursorScreenPos(ctx, vx + bw + 4, chy)
  if U.key("chone", "Ch " .. (chan > 0 and chan or S.mchan or 1), chan > 0, bw, 20, "One channel (click: choose)") then
    r.ImGui_OpenPopup(ctx, "##chpop")
  end
  if r.ImGui_BeginPopup(ctx, "##chpop") then
    for k = 1, 16 do
      if r.ImGui_MenuItem(ctx, "Channel " .. k, nil, chan == k) then
        r.TrackFX_SetParam(tr, li, pch, k)
        S.mchan = k
      end
    end
    r.ImGui_EndPopup(ctx)
  end
end

-- Macro-4: the four knobs under each other, each with its name (double-click: rename; kept in
-- the track)
function M.macro_name(tr, lg, k)
  local _, n = r.GetSetMediaTrackInfo_String(tr, "P_EXT:TKBIT_MN_" .. (lg:gsub("[{}]", "")) .. "_" .. k, "", false)
  return n ~= "" and n or ("Macro " .. k)
end
function D.macro4_editor(tr, li, lg, x, y, w, h, dl)
  local rowh = h / 4
  for k = 1, 4 do
    local p = F.param_index_c(tr, li, "Macro " .. k)
    if p then
      local ry = y + (k - 1) * rowh
      local cx, cy = x + w / 2, ry + rowh / 2 - 6
      r.ImGui_SetCursorScreenPos(ctx, x + 4, ry)
      r.ImGui_InvisibleButton(ctx, "##mk" .. k, math.max(1, w - 8), math.max(1, rowh - 16))
      local hov, act = r.ImGui_IsItemHovered(ctx), r.ImGui_IsItemActive(ctx)
      local v = r.TrackFX_GetParam(tr, li, p)
      if act then
        local _, dy = r.ImGui_GetMouseDelta(ctx)
        if dy ~= 0 then
          v = H.clamp(v - dy / 160 * (H.mods() and 0.1 or 1), 0, 1)
          r.TrackFX_SetParam(tr, li, p, v)
        end
      end
      if r.ImGui_IsItemDeactivated(ctx) then r.Undo_OnStateChangeEx2(0, "Devices: macro " .. k, 2, -1) end
      local rad = math.max(7, math.min(12, rowh / 2 - 12))
      U.knob(dl, cx, cy, rad, v, v, false, hov)
      if hov and not act then r.ImGui_SetTooltip(ctx, ("%d %%"):format(math.floor(v * 100 + 0.5))) end
      -- the name
      local name = M.macro_name(tr, lg, k)
      local nm = H.fit(name, w - 6)
      local nw = r.ImGui_CalcTextSize(ctx, nm)
      r.ImGui_SetCursorScreenPos(ctx, x + 2, ry + rowh - 16)
      r.ImGui_InvisibleButton(ctx, "##mn" .. k, math.max(1, w - 4), 14)
      if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
        S.mrename = { lg = lg, k = k, buf = name }
        r.ImGui_OpenPopup(ctx, "##mren" .. k)
      end
      if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Double-click: rename") end
      r.ImGui_DrawList_AddText(dl, x + (w - nw) / 2, ry + rowh - 16, C.label, nm)
      if r.ImGui_BeginPopup(ctx, "##mren" .. k) then
        local m = S.mrename
        if m and m.lg == lg and m.k == k then
          if r.ImGui_IsWindowAppearing(ctx) then r.ImGui_SetKeyboardFocusHere(ctx) end
          r.ImGui_SetNextItemWidth(ctx, 140)
          local ch, buf = r.ImGui_InputText(ctx, "##mrenbuf", m.buf)
          if ch then m.buf = buf end
          if r.ImGui_IsItemDeactivatedAfterEdit(ctx) or r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Enter(), false) then
            r.GetSetMediaTrackInfo_String(tr, "P_EXT:TKBIT_MN_" .. (lg:gsub("[{}]", "")) .. "_" .. k,
              m.buf == ("Macro " .. k) and "" or m.buf, true)
            r.ImGui_CloseCurrentPopup(ctx)
          end
        end
        r.ImGui_EndPopup(ctx)
      end
    end
  end
end

---------------------------------------------------------------- Keytrack+: the curve editor
-- The curve lives in the JSFX's hidden sliders ("Points", "P1 x" .. "P8 y"); the window is
-- Bitwig's floating Keytrack+ editor: drag the points, double-click to add or remove one,
-- right-click a point to remove it, shapes, bipolar and snap in the toolbar.
function M.kt_points(tr, li)
  local np = F.param_index_c(tr, li, "Points")
  if not np then return nil end
  local n = math.max(2, math.min(8, math.floor(r.TrackFX_GetParam(tr, li, np) + 0.5)))
  local out = {}
  for k = 1, n do
    local px, py = F.param_index_c(tr, li, "P" .. k .. " x"), F.param_index_c(tr, li, "P" .. k .. " y")
    if not (px and py) then return nil end
    out[k] = { r.TrackFX_GetParam(tr, li, px), r.TrackFX_GetParam(tr, li, py) }
  end
  return out
end
function M.kt_write(tr, li, pts)
  table.sort(pts, function(a, b) return a[1] < b[1] end)
  local function put(p, v)
    if p and math.abs(r.TrackFX_GetParamNormalized(tr, li, p) - v) > 1e-5 then r.TrackFX_SetParamNormalized(tr, li, p, v) end
  end
  put(F.param_index_c(tr, li, "Points"), (#pts - 2) / 6)
  for k = 1, #pts do
    put(F.param_index_c(tr, li, "P" .. k .. " x"), H.clamp(pts[k][1], 0, 1))
    put(F.param_index_c(tr, li, "P" .. k .. " y"), H.clamp(pts[k][2], 0, 1))
  end
end
local NOTE = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
function H.note(n) n = math.floor(n + 0.5); return NOTE[n % 12 + 1] .. (n // 12 - 1) end
local KT_SHAPES = {
  { "Ramp up", { { 0, 0 }, { 1, 1 } } },
  { "Ramp down", { { 0, 1 }, { 1, 0 } } },
  { "Triangle", { { 0, 0 }, { 0.5, 1 }, { 1, 0 } } },
  { "Step", { { 0, 0 }, { 0.495, 0 }, { 0.505, 1 }, { 1, 1 } } },
}

function D.kt_window()
  local lg = S.ktwin
  if not lg then return end
  local tr = F.track()
  local li = tr and F.index(tr, lg)
  if not li then S.ktwin = nil; return end
  r.ImGui_SetNextWindowSize(ctx, 460, 310, r.ImGui_Cond_FirstUseEver())
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), 0x1A1A1AFF)
  local vis, open = r.ImGui_Begin(ctx, "Keytrack+  -  " .. F.name(tr, F.index(tr, S.lfo_owner[lg] or lg) or li) .. "###tkbitkt", true,
    r.ImGui_WindowFlags_NoCollapse() | (r.ImGui_WindowFlags_NoDocking and r.ImGui_WindowFlags_NoDocking() or 0))
  r.ImGui_PopStyleColor(ctx)
  if vis then
    D.kt_editor(tr, li, lg)
    r.ImGui_End(ctx)
  end
  if not open then S.ktwin = nil end
end

function D.kt_editor(tr, li, lg)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local aw, ah = r.ImGui_GetContentRegionAvail(ctx)
  local pts = M.kt_points(tr, li)
  if not pts then
    U.text_col(C.dim, "This Keytrack is from before the curve: add a new one, or reopen the project.")
    return
  end
  local cw, ch = aw, math.max(60, ah - 52)
  local pad = 8
  local gx, gy, gw, gh = x + pad, y + pad, cw - 2 * pad, ch - 2 * pad
  local bip = M.bipolar(tr, li)
  local snap = S.ktsnap ~= false
  local function SX(px) return gx + px * gw end
  local function SY(py) return gy + (1 - py) * gh end
  local function snapped(px, py)
    if snap then px, py = math.floor(px * 10 + 0.5) / 10, math.floor(py * 6 + 0.5) / 6 end
    return H.clamp(px, 0, 1), H.clamp(py, 0, 1)
  end
  -- the canvas: grid 10 x 6, the curve filled to its base line (the middle when bipolar)
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + cw, y + ch, C.canvas, 3)
  r.ImGui_DrawList_AddRect(dl, x, y, x + cw, y + ch, C.pane_edge, 3, 0, 1)
  for k = 1, 9 do r.ImGui_DrawList_AddLine(dl, SX(k / 10), gy, SX(k / 10), gy + gh, C.grid, 1) end
  for k = 1, 5 do r.ImGui_DrawList_AddLine(dl, gx, SY(k / 6), gx + gw, SY(k / 6), C.grid, 1) end
  local base = SY(bip and 0.5 or 0)
  for k = 1, #pts - 1 do
    local a, b = pts[k], pts[k + 1]
    local steps = 12
    for st = 0, steps - 1 do
      local t1, t2 = st / steps, (st + 1) / steps
      local x1, x2 = SX(a[1] + (b[1] - a[1]) * t1), SX(a[1] + (b[1] - a[1]) * t2)
      local y1, y2 = SY(a[2] + (b[2] - a[2]) * t1), SY(a[2] + (b[2] - a[2]) * t2)
      r.ImGui_DrawList_AddQuadFilled(dl, x1, y1, x2, y2, x2, base, x1, base, C.kt_fill)
    end
  end
  for _, pt in ipairs(pts) do r.ImGui_DrawList_PathLineTo(dl, SX(pt[1]), SY(pt[2])) end
  r.ImGui_DrawList_PathStroke(dl, C.kt, 0, 2)
  -- the key playing now
  local kp = F.param_index_c(tr, li, "Key")
  if kp then
    local kx = SX(r.TrackFX_GetParam(tr, li, kp))
    r.ImGui_DrawList_AddLine(dl, kx, gy, kx, gy + gh, 0xFFFFFF30, 1)
    local out = F.param_index_cached(tr, li)
    local ov = r.TrackFX_GetParamNormalized(tr, li, out)
    r.ImGui_DrawList_AddCircleFilled(dl, kx, SY(H.clamp(ov, 0, 1)), 3, C.mod, 10)
  end
  -- editing: one hit area over the canvas
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  r.ImGui_InvisibleButton(ctx, "##ktcanvas", math.max(1, cw), math.max(1, ch))
  local hov = r.ImGui_IsItemHovered(ctx)
  local mx, my = r.ImGui_GetMousePos(ctx)
  local near
  for k, pt in ipairs(pts) do
    local dx, dy = SX(pt[1]) - mx, SY(pt[2]) - my
    if dx * dx + dy * dy < 81 then near = k end
  end
  if r.ImGui_IsItemActivated(ctx) then S.ktdrag = near end
  if r.ImGui_IsItemActive(ctx) and S.ktdrag and pts[S.ktdrag] then
    local k = S.ktdrag
    local px, py = snapped((mx - gx) / gw, 1 - (my - gy) / gh)
    if k == 1 then px = 0 elseif k == #pts then px = 1
    else px = H.clamp(px, pts[k - 1][1] + 0.001, pts[k + 1][1] - 0.001) end
    if px ~= pts[k][1] or py ~= pts[k][2] then
      pts[k] = { px, py }
      M.kt_write(tr, li, pts)
    end
  end
  if r.ImGui_IsItemDeactivated(ctx) and S.ktdrag then
    S.ktdrag = nil
    r.Undo_OnStateChangeEx2(0, "Devices: Keytrack curve", 2, -1)
  end
  local function remove(k)
    if k and k > 1 and k < #pts then
      table.remove(pts, k)
      M.kt_write(tr, li, pts)
      r.Undo_OnStateChangeEx2(0, "Devices: Keytrack point", 2, -1)
    end
  end
  if hov and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
    if near then
      remove(near)
    elseif #pts < 8 then
      local px, py = snapped((mx - gx) / gw, 1 - (my - gy) / gh)
      if px > 0 and px < 1 then
        pts[#pts + 1] = { px, py }
        M.kt_write(tr, li, pts)
        r.Undo_OnStateChangeEx2(0, "Devices: Keytrack point", 2, -1)
      end
    end
  end
  if hov and r.ImGui_IsItemClicked(ctx, 1) then remove(near) end
  for k, pt in ipairs(pts) do
    local big = k == near or k == S.ktdrag
    r.ImGui_DrawList_AddCircleFilled(dl, SX(pt[1]), SY(pt[2]), big and 6 or 4.5, C.kt, 12)
    if big then r.ImGui_DrawList_AddCircle(dl, SX(pt[1]), SY(pt[2]), 7, C.text, 12, 1.2) end
  end
  if hov and not r.ImGui_IsItemActive(ctx) then
    r.ImGui_SetTooltip(ctx, near and ("Point " .. near .. (near > 1 and near < #pts and "\nDouble- or right-click: remove" or ""))
      or "Double-click: add a point (8 at most)")
  end
  -- the note range under it: Low ... High (drag sideways, a semitone per 6 px)
  local ny = y + ch + 4
  local function notebox(id, name, bx, align)
    local p = F.param_index_c(tr, li, name)
    if not p then return end
    local v = r.TrackFX_GetParam(tr, li, p)
    local txt = H.note(v)
    local tw = r.ImGui_CalcTextSize(ctx, txt)
    local tx = align == "r" and bx - tw - 8 or bx
    r.ImGui_SetCursorScreenPos(ctx, tx - 4, ny)
    r.ImGui_InvisibleButton(ctx, id, tw + 16, 18)
    if r.ImGui_IsItemActive(ctx) then
      local dx = r.ImGui_GetMouseDelta(ctx)
      S.ktacc = (S.ktacc or 0) + dx / 6
      local step = S.ktacc >= 1 and math.floor(S.ktacc) or (S.ktacc <= -1 and -math.floor(-S.ktacc) or 0)
      if step ~= 0 then
        S.ktacc = S.ktacc - step
        r.TrackFX_SetParamNormalized(tr, li, p, H.clamp(v + step, 0, 127) / 127)
      end
    end
    if r.ImGui_IsItemDeactivated(ctx) then S.ktacc = 0; r.Undo_OnStateChangeEx2(0, "Devices: Keytrack range", 2, -1) end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, name .. ": drag sideways") end
    r.ImGui_DrawList_AddRectFilled(dl, tx - 4, ny, tx + tw + 12, ny + 18, C.box, 3)
    r.ImGui_DrawList_AddText(dl, tx + 4, ny + 2, C.value, txt)
  end
  notebox("##ktlo", "Low note", x + 4, "l")
  notebox("##kthi", "High note", x + cw, "r")
  local mid = "the key, low to high"
  local midw = r.ImGui_CalcTextSize(ctx, mid)
  r.ImGui_DrawList_AddText(dl, x + (cw - midw) / 2, ny + 2, C.dim, mid)
  -- the toolbar: shapes, bipolar, snap, more
  local ty = ny + 24
  r.ImGui_DrawList_AddText(dl, x + 4, ty + 3, C.dim, "TOOL")
  local bx = x + 44
  for k, sh in ipairs(KT_SHAPES) do
    r.ImGui_SetCursorScreenPos(ctx, bx, ty)
    if r.ImGui_InvisibleButton(ctx, "##kts" .. k, 24, 20) then
      local np = {}
      for n, pt in ipairs(sh[2]) do np[n] = { pt[1], pt[2] } end
      M.kt_write(tr, li, np)
      r.Undo_OnStateChangeEx2(0, "Devices: Keytrack shape", 2, -1)
    end
    local h2 = r.ImGui_IsItemHovered(ctx)
    if h2 then r.ImGui_SetTooltip(ctx, sh[1]) end
    for n, pt in ipairs(sh[2]) do r.ImGui_DrawList_PathLineTo(dl, bx + 4 + pt[1] * 16, ty + 16 - pt[2] * 12) end
    r.ImGui_DrawList_PathStroke(dl, h2 and C.text or C.label, 0, 1.4)
    bx = bx + 28
  end
  bx = bx + 8
  r.ImGui_SetCursorScreenPos(ctx, bx, ty)
  if U.key("ktbip", "\u{00B1}", bip, 26, 20, bip and "Bipolar: around the value" or "Unipolar: up from the value") then
    M.set_bipolar(tr, lg, not bip)
  end
  bx = bx + 34
  r.ImGui_SetCursorScreenPos(ctx, bx, ty)
  if r.ImGui_InvisibleButton(ctx, "##ktsnap", 40, 20) then S.ktsnap = not snap end
  local sh2 = r.ImGui_IsItemHovered(ctx)
  r.ImGui_DrawList_AddText(dl, bx + 2, ty + 3, snap and C.accent or (sh2 and C.text or C.dim), "SNAP")
  if snap then r.ImGui_DrawList_AddLine(dl, bx + 2, ty + 18, bx + 36, ty + 18, C.accent, 1) end
  r.ImGui_DrawList_AddText(dl, bx + 46, ty + 3, C.dim, "10 x 6")
  -- more: glide, amount
  r.ImGui_SetCursorScreenPos(ctx, x + cw - 22, ty)
  if r.ImGui_InvisibleButton(ctx, "##ktmore", 20, 20) then r.ImGui_OpenPopup(ctx, "##ktextra") end
  local mh = r.ImGui_IsItemHovered(ctx)
  for k = -1, 1 do r.ImGui_DrawList_AddCircleFilled(dl, x + cw - 12 + k * 4, ty + 10, 1.5, mh and C.text or C.dim, 6) end
  if mh then r.ImGui_SetTooltip(ctx, "Glide, Amount") end
  if r.ImGui_BeginPopup(ctx, "##ktextra") then
    D.extra_items(tr, li, lg, EXTRA.keytrack)
    r.ImGui_EndPopup(ctx)
  end
end

-- the ADSR's shape: attack, decay to the sustain level, a held stretch, release (times as
-- square roots, so short and long both read)
function D.adsr_shape(tr, li, x, y, w, h, col, dl)
  local function g(n, d) local p = F.param_index_c(tr, li, n); return p and r.TrackFX_GetParam(tr, li, p) or d end
  local a, d, su, rl = math.sqrt(g("Attack (ms)", 10)), math.sqrt(g("Decay (ms)", 300)), g("Sustain", 0.6), math.sqrt(g("Release (ms)", 400))
  local hold = (a + d + rl) * 0.35 + 1
  local tot = a + d + hold + rl
  local function X(t) return x + t / tot * w end
  r.ImGui_DrawList_PathLineTo(dl, X(0), y + h)
  r.ImGui_DrawList_PathLineTo(dl, X(a), y)
  r.ImGui_DrawList_PathLineTo(dl, X(a + d), y + (1 - su) * h)
  r.ImGui_DrawList_PathLineTo(dl, X(a + d + hold), y + (1 - su) * h)
  r.ImGui_DrawList_PathLineTo(dl, X(tot), y + h)
  r.ImGui_DrawList_PathStroke(dl, col, 0, 1.8)
end

-- a routing arrow button for one source (out = its parameter, nil = Output)
function D.route_btn(id, lg, out, cx, cy, dl, tip, tr, label)
  local routing = S.route == lg and S.route_out == out
  r.ImGui_SetCursorScreenPos(ctx, cx - 11, cy - 8)
  if r.ImGui_InvisibleButton(ctx, id, 22, 16) then
    if routing then S.route, S.route_out, S.route_src = nil, nil, nil
    else
      S.route, S.route_out = lg, out
      S.route_src = { track = r.GetTrackGUID(tr), lg = lg, out = out, label = label }
    end
  end
  local rh = r.ImGui_IsItemHovered(ctx)
  U.i_mod(dl, cx, cy, routing and ((r.time_precise() * 3) % 1 < 0.5 and C.accent or C.mod) or (rh and C.text or C.mod))
  if rh then r.ImGui_SetTooltip(ctx, routing and "Click a parameter and drag. Click here (or Esc) to finish." or tip) end
end

-- the tiles that are their own control (as Bitwig's): Macro-4 (four routing arrows, its knobs in
-- the editor), Button (one key), Buttons (A and B, each its own routing)
function D.tile_controls(tr, li, lg, kind, x, y, w, th, dl, owner, on, routing, shown)
  local function open_page()
    S.mexp[owner] = S.mexp[owner] ~= lg and lg or nil
    S.guid = owner
  end
  if shown then r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + th, C.tile_on) end
  if kind == "macro4" then
    -- the tile: a click unfolds the editor (the four knobs); one routing arrow per macro
    r.ImGui_SetCursorScreenPos(ctx, x, y)
    if r.ImGui_InvisibleButton(ctx, "##tile", math.max(1, w - 30), math.max(1, th)) then open_page() end
    if r.ImGui_IsItemClicked(ctx, 1) then r.ImGui_OpenPopup(ctx, "##tilemenu") end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Macro-4\nClick: its knobs. Right-click: more") end
    local rowh = (th - 8) / 4
    for k = 1, 4 do
      local p = F.param_index_c(tr, li, "Macro " .. k)
      if p then
        local cy = y + 4 + (k - 0.5) * rowh
        local mv = r.TrackFX_GetParam(tr, li, p)
        r.ImGui_DrawList_AddRectFilled(dl, x + 6, cy - 2, x + 6 + (w - 46) * mv, cy + 2, C.k_body_hi, 2)
        D.route_btn("##mr" .. k, lg, p, x + w - 22, cy, dl, "Route " .. M.macro_name(tr, lg, k) .. ": click, then a parameter, and drag",
          tr, M.macro_name(tr, lg, k))
      end
    end
    U.arrow(dl, x + w - 5, y + th / 2, 1, shown and C.text or C.dim)
  else
    local keys = kind == "button" and { { "Button", "Button" } } or { { "A", "A" }, { "B", "B" } }
    local mp = F.param_index_c(tr, li, "Mode")
    local momentary = mp and r.TrackFX_GetParam(tr, li, mp) >= 0.5
    local top = y + 6
    if kind == "buttons" then
      local tw = r.ImGui_CalcTextSize(ctx, "Buttons")
      r.ImGui_DrawList_AddText(dl, x + (w - tw) / 2, y + 3, C.label, "Buttons")
      top = y + 20
    end
    local kw = (w - 12 - (#keys - 1) * 4) / #keys
    local kh = math.min(24, th - (top - y) - 30)
    for n, kd in ipairs(keys) do
      local p = F.param_index_c(tr, li, kd[1])
      local kx = x + 6 + (n - 1) * (kw + 4)
      local ky = top + math.max(0, (th - (top - y) - 30 - kh) / 2)
      if p then
        local st = r.TrackFX_GetParam(tr, li, p) >= 0.5
        r.ImGui_SetCursorScreenPos(ctx, kx, ky)
        r.ImGui_InvisibleButton(ctx, "##key" .. n, math.max(1, kw), math.max(1, kh))
        local hov = r.ImGui_IsItemHovered(ctx)
        if momentary then
          if r.ImGui_IsItemActivated(ctx) then r.TrackFX_SetParam(tr, li, p, 1) end
          if r.ImGui_IsItemDeactivated(ctx) then r.TrackFX_SetParam(tr, li, p, 0) end
        elseif r.ImGui_IsItemClicked(ctx, 0) then
          r.TrackFX_SetParam(tr, li, p, st and 0 or 1)
          r.Undo_OnStateChangeEx2(0, "Devices: " .. kd[2], 2, -1)
        end
        if r.ImGui_IsItemClicked(ctx, 1) then r.ImGui_OpenPopup(ctx, "##tilemenu") end
        local top_c, bot_c = C.key_top, C.key_bot
        if st then top_c, bot_c = C.on_top, C.on_bot elseif hov then top_c, bot_c = C.seg_hi, 0x333333FF end
        r.ImGui_DrawList_AddRectFilled(dl, kx, ky, kx + kw, ky + kh, C.key_edge, 3)
        r.ImGui_DrawList_AddRectFilledMultiColor(dl, kx + 1, ky + 1, kx + kw - 1, ky + kh - 1, top_c, top_c, bot_c, bot_c)
        local t = H.fit(kd[2], kw - 4)
        local tw, th2 = r.ImGui_CalcTextSize(ctx, t)
        r.ImGui_DrawList_AddText(dl, kx + (kw - tw) / 2, ky + (kh - th2) / 2, st and 0x141414FF or C.text, t)
        if hov then r.ImGui_SetTooltip(ctx, (momentary and "Hold: on" or "Click: on / off") .. "\nRight-click: mode, smooth, more") end
        D.route_btn("##rt" .. n, lg, kind == "button" and nil or p, kx + kw / 2, ky + kh + 12, dl, "Routing: click, then a parameter, and drag",
          tr, kind == "button" and "Button" or ("Button " .. kd[1]))
      end
    end
  end
  D.tile_menu(tr, li, lg, kind, on, 0, open_page, owner)
end

-- one modulator tile, as Bitwig's: its picture and the routing button. Click: its controls (the
-- remote controls pane on its page); right-click: more. A Macro's tile is its knob: drag it.
function D.tile(tr, lg, x, y, w, th, dl, owner)
  local li = F.index(tr, lg)
  if not li then return end
  local kind = F.mod_kind(tr, li) or "lfo"
  local on = r.TrackFX_GetEnabled(tr, li)
  local out = F.param_index_cached(tr, li)
  local v = r.TrackFX_GetParamNormalized(tr, li, out)
  local routing = S.route == lg
  local shown = S.mexp[owner] == lg
  local vp = kind == "macro" and F.param_index_c(tr, li, "Value")
  if kind == "macro4" or kind == "button" or kind == "buttons" then
    return D.tile_controls(tr, li, lg, kind, x, y, w, th, dl, owner, on, routing, shown)
  end
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  r.ImGui_InvisibleButton(ctx, "##tile", w, math.max(1, th - 22))
  local hov, act = r.ImGui_IsItemHovered(ctx), r.ImGui_IsItemActive(ctx)
  local function open_page()                  -- its editor, unfolded to the right (Bitwig's ">")
    S.guid = owner
    if kind == "keytrack" then S.ktwin = S.ktwin ~= lg and lg or nil; return end   -- its own window
    S.mexp[owner] = S.mexp[owner] ~= lg and lg or nil
  end
  if vp then                                  -- the Macro: drag = its value, a click = its editor
    if r.ImGui_IsItemActivated(ctx) then S.tdrag = 0 end
    if act then
      local _, dy = r.ImGui_GetMouseDelta(ctx)
      if dy ~= 0 then
        S.tdrag = (S.tdrag or 0) + math.abs(dy)
        r.TrackFX_SetParam(tr, li, vp, H.clamp(r.TrackFX_GetParam(tr, li, vp) - dy / 160 * (H.mods() and 0.1 or 1), 0, 1))
      end
    end
    if r.ImGui_IsItemDeactivated(ctx) then
      if (S.tdrag or 0) < 2 then open_page() else r.Undo_OnStateChangeEx2(0, "Devices: macro", 2, -1) end
    end
  elseif r.ImGui_IsItemClicked(ctx, 0) then
    open_page()
  end
  if r.ImGui_IsItemClicked(ctx, 1) then r.ImGui_OpenPopup(ctx, "##tilemenu") end
  if shown or hov then r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + th, shown and C.tile_on or C.hover) end
  local cx0, cy0, cw, ch = x + 6, y + 8, w - 16, th - 34
  local col = on and C.accent or C.dim
  local shape, curve = 0, 0
  if kind == "lfo" then
    shape, curve = M.look(tr, li)
    for k = 0, 32 do
      local t = k / 32
      r.ImGui_DrawList_PathLineTo(dl, cx0 + t * cw, cy0 + (1 - M.shape(shape, t, curve)) * ch)
    end
    r.ImGui_DrawList_PathStroke(dl, col, 0, 1.8)
  elseif kind == "steps" then
    local n, pos = M.steps(tr, li)
    local bw = cw / n
    for k = 1, n do
      local p = F.param_index_c(tr, li, "Step " .. k)
      local sv = p and r.TrackFX_GetParam(tr, li, p) or 0
      r.ImGui_DrawList_AddRectFilled(dl, cx0 + (k - 1) * bw + 0.5, cy0 + (1 - sv) * ch, cx0 + k * bw - 0.5, cy0 + ch,
        (k == pos + 1 and on) and C.accent or 0x6A6A6AFF)
    end
  elseif kind == "adsr" then
    D.adsr_shape(tr, li, cx0, cy0, cw, ch, col, dl)
  elseif kind == "keytrack" then
    -- a small keyboard on top, the curve under it (as Bitwig's Keytrack+)
    local kw = math.min(cw, 26)
    local kx0 = cx0 + (cw - kw) / 2
    r.ImGui_DrawList_AddRectFilled(dl, kx0, cy0 - 6, kx0 + kw, cy0 + 2, C.text, 1)
    for k = 1, 5 do
      local bx = kx0 + k * kw / 6
      r.ImGui_DrawList_AddRectFilled(dl, bx - 1.2, cy0 - 6, bx + 1.2, cy0 - 1, C.env_text)
    end
    local kp = M.kt_points(tr, li)
    local gy0, gh = cy0 + 6, ch - 6
    r.ImGui_DrawList_AddRectFilled(dl, cx0, gy0, cx0 + cw, gy0 + gh, C.headbox, 2)
    if kp then
      for _, pt in ipairs(kp) do r.ImGui_DrawList_PathLineTo(dl, cx0 + pt[1] * cw, gy0 + (1 - pt[2]) * gh) end
    else
      r.ImGui_DrawList_PathLineTo(dl, cx0, gy0 + gh)
      r.ImGui_DrawList_PathLineTo(dl, cx0 + cw, gy0)
    end
    r.ImGui_DrawList_PathStroke(dl, on and C.kt or C.dim, 0, 1.6)
  elseif kind == "macro" then
    local mv = vp and r.TrackFX_GetParam(tr, li, vp) or 0
    local rad = math.max(8, math.min(cw, ch) / 2 - 4)
    U.knob(dl, cx0 + cw / 2, cy0 + ch / 2, rad, mv, mv, false, hov)
  else                                        -- Random, Follower, MIDI: the last ~2 s of output
    if kind == "midi" then
      local tp, cc = F.param_index_c(tr, li, "Type"), F.param_index_c(tr, li, "CC")
      local t = tp and math.floor(r.TrackFX_GetParam(tr, li, tp) + 0.5) or 0
      local lbl = ({ "CC " .. (cc and math.floor(r.TrackFX_GetParam(tr, li, cc) + 0.5) or 1), "Bend", "Pressure", "Velocity" })[t + 1]
      r.ImGui_DrawList_AddText(dl, cx0, cy0 - 2, C.label, lbl or "")
    end
    local hst = M.history(lg, v)
    local n = #hst
    for k = 1, n do
      local idx = (hst.i + k - 1) % n + 1
      r.ImGui_DrawList_PathLineTo(dl, cx0 + (k - 1) / math.max(1, 63) * cw, cy0 + (1 - hst[idx]) * ch)
    end
    r.ImGui_DrawList_PathStroke(dl, col, 0, 1.6)
  end
  if kind ~= "macro" then                     -- the output, a thin meter at the left
    r.ImGui_DrawList_AddRectFilled(dl, x + 2, cy0, x + 4, cy0 + ch, C.k_track)
    r.ImGui_DrawList_AddRectFilled(dl, x + 2, cy0 + (1 - v) * ch, x + 4, cy0 + ch, C.mod)
  end
  U.arrow(dl, x + w - 5, y + (th - 22) / 2, 1, shown and C.text or C.dim)   -- Bitwig's ">"
  r.ImGui_DrawList_AddText(dl, x + 26, y + th - 19, C.dim, H.fit(MODS[kind].label, w - 30))
  if hov and not act then
    local n = #(S.routes[lg] or {})
    r.ImGui_SetTooltip(ctx, MODS[kind].menu .. (kind == "lfo" and (" - " .. SHAPES[shape + 1]) or "") .. ", " .. n
      .. (n == 1 and " target" or " targets") .. (kind == "macro" and "\nDrag: its value. Click: its editor." or "\nClick: its editor.")
      .. " Right-click: more")
  end
  -- the routing button
  local by = y + th - 22
  r.ImGui_SetCursorScreenPos(ctx, x + 2, by)
  if r.ImGui_InvisibleButton(ctx, "##route", 22, 18) then
    S.route, S.route_out = (not routing) and lg or nil, nil
    S.route_src = S.route and { track = r.GetTrackGUID(tr), lg = lg, label = MODS[kind].label } or nil
  end
  local rh = r.ImGui_IsItemHovered(ctx)
  local rc = routing and ((r.time_precise() * 3) % 1 < 0.5 and C.accent or C.mod) or (rh and C.text or C.mod)
  U.i_mod(dl, x + 14, by + 9, rc)
  if rh then
    r.ImGui_SetTooltip(ctx, routing and "Click a parameter and drag up or down for the amount.\nClick here (or Esc) to finish."
      or "Routing: click, then click a parameter and drag")
  end
  D.tile_menu(tr, li, lg, kind, on, shape, open_page, owner)
end
function D.tile_menu(tr, li, lg, kind, on, shape, open_page, owner)
  if r.ImGui_BeginPopup(ctx, "##tilemenu") then
    if kind == "lfo" then
      local shp = F.param_index_c(tr, li, "Shape")
      for k, nm in ipairs(SHAPES) do
        if r.ImGui_MenuItem(ctx, nm, nil, shape == k - 1) and shp then r.TrackFX_SetParam(tr, li, shp, k - 1) end
      end
      r.ImGui_Separator(ctx)
    end
    if EXTRA[kind] and (kind == "button" or kind == "buttons") then
      D.extra_items(tr, li, lg, EXTRA[kind])
      r.ImGui_Separator(ctx)
    elseif r.ImGui_MenuItem(ctx, "Its editor", nil, S.mexp[owner] == lg) then
      open_page()
    end
    if kind == "lfo" and owner ~= "TRACK" and r.ImGui_MenuItem(ctx, "Its remote controls page") then
      S.vr[owner], S.rcmod[owner] = true, lg
    end
    if r.ImGui_MenuItem(ctx, "Active", nil, on) then r.TrackFX_SetEnabled(tr, li, not on) end
    if r.ImGui_MenuItem(ctx, "Show the JSFX") then r.TrackFX_Show(tr, li, 3) end
    for _, rt in ipairs(S.routes[lg] or {}) do
      local ti = F.index(tr, rt.tgt)
      if ti then
        local pn = select(2, r.TrackFX_GetParamName(tr, ti, rt.p, ""))
        if r.ImGui_MenuItem(ctx, "Remove routing: " .. F.name(tr, ti) .. " / " .. pn) then M.unroute(tr, ti, rt.p) end
      end
    end
    r.ImGui_Separator(ctx)
    if r.ImGui_MenuItem(ctx, "Delete") then H.later(function() M.delete_lfo(tr, lg) end) end
    r.ImGui_EndPopup(ctx)
  end
end

-- Bitwig's Modulators pane: three slots to start with, three more when they are full
-- (Bitwig: three slots; when they are full a new column of three appears, the pane grows)
function M.mod_cols(guid) return math.floor(#(S.owned[guid] or {}) / 3) + 1 end
function D.mods(tr, guid, x, y, w, h)
  local list = S.owned[guid] or {}
  local cols = M.mod_cols(guid)
  local n = 3 * cols
  local th = math.floor(h / 3)
  local cw = (w - (cols - 1) * 2) / cols
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  if not r.ImGui_BeginChild(ctx, "##mods", w, h, 0, r.ImGui_WindowFlags_NoScrollbar()) then return end
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x0, y0 = r.ImGui_GetCursorScreenPos(ctx)
  for k = 1, n do
    local col, row = (k - 1) // 3, (k - 1) % 3
    local tx, ty = x0 + col * (cw + 2), y0 + row * th
    r.ImGui_PushID(ctx, k)
    if list[k] then
      D.tile(tr, list[k], tx, ty, cw, th - 1, dl, guid)
    else
      r.ImGui_SetCursorScreenPos(ctx, tx, ty)
      if r.ImGui_InvisibleButton(ctx, "##add", cw, th - 1) then r.ImGui_OpenPopup(ctx, "##addmod") end
      local hov = r.ImGui_IsItemHovered(ctx)
      if hov then r.ImGui_DrawList_AddRectFilled(dl, tx, ty, tx + cw, ty + th - 1, C.hover) end
      U.plus(dl, tx + cw / 2, ty + th / 2, hov and C.text or C.dim)
      if hov then r.ImGui_SetTooltip(ctx, "Add a modulator") end
      if r.ImGui_BeginPopup(ctx, "##addmod") then
        U.text_col(C.dim, "MODULATORS")
        for _, mk in ipairs(MODS.order) do
          if r.ImGui_MenuItem(ctx, MODS[mk].menu) then
            local li = M.add_mod(tr, guid, mk)
            if li then S.vr[guid], S.rcmod[guid] = true, r.TrackFX_GetFXGUID(tr, li) end
          end
        end
        r.ImGui_EndPopup(ctx)
      end
    end
    if row < 2 then r.ImGui_DrawList_AddLine(dl, tx, ty + th - 0.5, tx + cw, ty + th - 0.5, C.pane_edge, 1) end
    if col > 0 and row == 0 then r.ImGui_DrawList_AddLine(dl, tx - 1, y0, tx - 1, y0 + 3 * th, C.pane_edge, 1) end
    r.ImGui_PopID(ctx)
  end
  r.ImGui_SetCursorScreenPos(ctx, x0, y0 + 3 * th)
  r.ImGui_Dummy(ctx, 1, 0)
  r.ImGui_EndChild(ctx)
end

function D.pane(dl, x1, y1, x2, y2)
  r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x2, y2, C.pane, 4)
  r.ImGui_DrawList_AddRect(dl, x1, y1, x2, y2, C.pane_edge, 4, 0, 1)
end

-- the modulator tiles (a column of 3 per 3) and the unfolded editor of one: their width, and
-- drawing them; owner = a device's GUID, or "TRACK" for the track's own modulators
function D.modpanes_w(tr, owner)
  if not S.vm[owner] then return 0 end
  local ex = S.mexp[owner]
  local exli = ex and F.index(tr, ex)
  if ex and not exli then S.mexp[owner], ex = nil, nil end
  local exkind = ex and F.mod_kind(tr, exli)
  return MPW * M.mod_cols(owner) + (exkind and (EXW[exkind] or 4 * SLOT + 16) or 0)
end
function D.modpanes(tr, owner, bx, y, h, dl)
  if not S.vm[owner] then return 0 end
  local mpw = MPW * M.mod_cols(owner)
  D.pane(dl, bx + 1, y + 3, bx + mpw - 2, y + h - 3)
  D.mods(tr, owner, bx + 2, y + 4, mpw - 4, h - 8)
  local w = mpw
  local ex = S.mexp[owner]
  local exli = ex and F.index(tr, ex)
  local exkind = exli and F.mod_kind(tr, exli)
  if exkind then                              -- the unfolded modulator editor, right of the tiles
    local exw = EXW[exkind] or 4 * SLOT + 16
    D.pane(dl, bx + w + 1, y + 3, bx + w + exw - 2, y + h - 3)
    D.mexp(tr, exli, ex, exkind, bx + w + 2, y + 5, exw - 4, h - 10, dl)
    w = w + exw
  end
  return w
end

-- one plug-in device; returns its width (it grows with the panes that are open)
function D.device(tr, i, x, y, h)
  local guid = r.TrackFX_GetFXGUID(tr, i)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local on = r.TrackFX_GetEnabled(tr, i)
  local sel = guid == S.guid
  local lfo = F.is_lfo(tr, i)
  local name = F.name(tr, i)
  local pl0 = RC.plugin(tr, i)
  if S.vr[guid] == nil then S.vr[guid] = false end
  if S.vm[guid] == nil then S.vm[guid] = S.owned[guid] ~= nil end
  local showr, showm = S.vr[guid], S.vm[guid]
  local nmods = #(S.owned[guid] or {})
  local w = STRIP + D.modpanes_w(tr, guid) + (showr and RPW or 0) + LW + 2
  r.ImGui_PushID(ctx, guid)
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, C.dev, 6)
  -- the strip (Bitwig's device header): power and presets at the top, the name upwards, then
  -- the plug-in window, the remote controls and the modulators at the bottom
  if D.sicon("##pow", x, y + 4, U.power, on, on and "Bypass" or "Switch on", dl) then r.TrackFX_SetEnabled(tr, i, not on) end
  if D.sicon("##fold", x, y + 24, U.folder, false, "Presets", dl) then r.ImGui_OpenPopup(ctx, "##preset") end
  D.preset_menu(tr, i)
  local open = r.TrackFX_GetOpen(tr, i)
  local by = y + h - 22
  if D.sicon("##mod", x, by, U.i_mod, showm, "Modulators" .. (nmods > 0 and (" (" .. nmods .. ")") or ""), dl) then
    S.vm[guid] = not showm
  end
  if D.sicon("##vr", x, by - 20, U.i_remote, showr, "Remote controls" ..
    (pl0 and #pl0.pages > 0 and (" (" .. #pl0.pages .. " pages)") or ""), dl) then S.vr[guid] = not showr end
  if D.sicon("##open", x, by - 40, U.window, open, open and "Close the plug-in window" or "Open the plug-in window", dl) then
    r.TrackFX_Show(tr, i, open and 2 or 3)
  end
  local ny0, ny1 = y + 46, by - 44 - (lfo and 14 or 0)
  r.ImGui_SetCursorScreenPos(ctx, x, ny0)
  if r.ImGui_InvisibleButton(ctx, "##strip", STRIP, math.max(1, ny1 - ny0)) then S.guid = guid end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, name) end
  U.vcenter(dl, x + STRIP / 2 - 4.5, ny0, ny1, name, on and C.text or C.dim, 1.5, 1.6)
  if lfo then r.ImGui_DrawList_AddCircleFilled(dl, x + STRIP / 2, ny1 + 8, 3.5, C.mod, 12) end
  local bx = x + STRIP
  local pl, page = pl0, nil
  -- every pane is its own dark box with a grey edge (Bitwig): remote controls, the modulator
  -- tiles, then the joker and the list under the search field
  if showr then
    D.pane(dl, bx + 1, y + 3, bx + RPW - 2, y + h - 3)
    r.ImGui_PushFont(ctx, font, 12)
    pl, page = D.remote(tr, i, guid, bx + 8, y + 9, RPW - 16, dl)
    r.ImGui_PopFont(ctx)
    bx = bx + RPW
  end
  bx = bx + D.modpanes(tr, guid, bx, y, h, dl)
  local jy, ly = y + 27, y + 27 + ROW + 5
  D.search(guid, bx + 2, y + 4, LW - 4, dl)
  D.pane(dl, bx + 1, jy, bx + LW - 1, jy + ROW + 2)
  D.joker(tr, i, guid, bx + 2, jy + 1, LW - 4, dl)
  D.pane(dl, bx + 1, ly, bx + LW - 1, y + h - 3)
  D.list(tr, i, guid, bx + 2, ly + 1, LW - 4, y + h - 4 - (ly + 1))
  D.param_menu(tr, i, guid)
  D.card_menus(tr, i, guid, pl, page)
  r.ImGui_DrawList_AddRect(dl, x, y, x + w, y + h, sel and C.dev_sel or C.dev_edge, 6, 0, 1.5)
  r.ImGui_PopID(ctx)
  return w
end

-- the track-type icons of the track strip (Bitwig's: a crown, a group, keys, a wave)
function U.tracktype(dl, cx, cy, kind, col)
  if kind == "master" then
    r.ImGui_DrawList_PathLineTo(dl, cx - 6, cy + 4)
    r.ImGui_DrawList_PathLineTo(dl, cx - 6, cy - 3)
    r.ImGui_DrawList_PathLineTo(dl, cx - 3, cy)
    r.ImGui_DrawList_PathLineTo(dl, cx, cy - 5)
    r.ImGui_DrawList_PathLineTo(dl, cx + 3, cy)
    r.ImGui_DrawList_PathLineTo(dl, cx + 6, cy - 3)
    r.ImGui_DrawList_PathLineTo(dl, cx + 6, cy + 4)
    r.ImGui_DrawList_PathFillConvex(dl, col)
  elseif kind == "group" then
    r.ImGui_DrawList_AddRect(dl, cx - 6, cy - 5, cx + 4, cy + 3, col, 1, 0, 1.2)
    r.ImGui_DrawList_AddRectFilled(dl, cx - 3, cy - 2, cx + 7, cy + 6, col, 1)
  elseif kind == "instrument" then
    r.ImGui_DrawList_AddRectFilled(dl, cx - 7, cy - 5, cx + 7, cy + 5, col, 1)
    for k = 1, 3 do
      local kx = cx - 7 + k * 3.5
      r.ImGui_DrawList_AddLine(dl, kx, cy - 5, kx, cy + 5, C.dev_strip, 1)
    end
    for _, kx in ipairs({ -3.5, 0, 3.5 }) do
      r.ImGui_DrawList_AddRectFilled(dl, cx + kx - 1.2, cy - 5, cx + kx + 1.2, cy + 0.5, C.dev_strip)
    end
  else
    local pts = { -7, 0, -5, -4, -3, 3, -1, -5, 1, 5, 3, -3, 5, 2, 7, 0 }
    for m = 1, #pts, 2 do r.ImGui_DrawList_PathLineTo(dl, cx + pts[m], cy + pts[m + 1]) end
    r.ImGui_DrawList_PathStroke(dl, col, 0, 1.4)
  end
end

-- what kind of track this is, by what is on it: master; a folder (group); MIDI when its first
-- item is MIDI, audio when it is audio; no items: a MIDI record input or an instrument = MIDI.
-- (TrackFX_GetInstrument alone was wrong: REAPER counts effects that take MIDI as instruments.)
function D.track_kind(tr)
  if tr == r.GetMasterTrack(0) then return "master" end
  if r.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") == 1 then return "group" end
  local item = r.GetTrackMediaItem(tr, 0)
  local take = item and r.GetActiveTake(item)
  if take then return r.TakeIsMIDI(take) and "instrument" or "audio" end
  local rec = r.GetMediaTrackInfo_Value(tr, "I_RECINPUT")
  if rec >= 4096 then return "instrument" end
  return r.TrackFX_GetInstrument(tr) >= 0 and "instrument" or "audio"
end

-- the track at the start of the row: its colour above and below, the name upwards
function D.trackstrip(tr, x, y, h)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local col = C.track
  local nc = r.GetTrackColor(tr)
  if nc and nc & 0x1000000 ~= 0 then
    local R, G, B = r.ColorFromNative(nc & 0xFFFFFF)
    col = (R << 24) | (G << 16) | (B << 8) | 0xFF
  end
  local sw = STRIP + 4
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + sw, y + h, C.dev_strip)
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + sw, y + 3, col)
  r.ImGui_DrawList_AddRectFilled(dl, x, y + h - 3, x + sw, y + h, col)
  -- what kind of track (REAPER knows): master, a folder (group), one with an instrument, audio
  local kind = D.track_kind(tr)
  U.tracktype(dl, x + sw / 2, y + 15, kind, C.text)
  local _, name = r.GetTrackName(tr)
  U.vcenter(dl, x + sw / 2 - 4.5, y + 28, y + h - 34, name, C.text, 1.5, 1.6)
  local nm = #(S.owned.TRACK or {})
  if D.sicon("##tmod", x + 2, y + h - 26, U.i_mod, S.vm.TRACK, (kind == "master" and "Project" or "Track")
    .. " modulators" .. (nm > 0 and (" (" .. nm .. ")") or "") .. "\n(route them to other tracks too)", dl) then
    S.vm.TRACK = not S.vm.TRACK
  end
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  r.ImGui_InvisibleButton(ctx, "##trackstrip", sw, math.max(1, h - 30))
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, name .. "  (" .. (kind == "instrument" and "MIDI" or kind) .. " track)") end
end

-- "+" between the devices: REAPER's FX browser
function D.plus(k, x, y, h)
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  if r.ImGui_InvisibleButton(ctx, "##plus" .. k, GAP, h) then r.Main_OnCommand(40271, 0) end
  local hov = r.ImGui_IsItemHovered(ctx)
  if hov then r.ImGui_SetTooltip(ctx, "Add an FX (REAPER's FX browser)") end
  U.plus(r.ImGui_GetWindowDrawList(ctx), x + GAP / 2, y + h / 2, hov and C.text or C.dim)
end

local MARGIN = 6
function D.row(tr)
  local x0, y = r.ImGui_GetCursorScreenPos(ctx)
  local aw, ah = r.ImGui_GetContentRegionAvail(ctx)
  -- the same margin above and below the devices (as Bitwig); the horizontal scrollbar's room
  -- (8 px) only when last frame's row did not fit
  local bar = (S.row_w or 0) > aw + 1 and 8 or 0
  y = y + MARGIN
  local h = math.max(120, ah - 2 * MARGIN - bar)
  D.trackstrip(tr, x0, y, h)
  local x = x0 + STRIP + 4
  if S.vm.TRACK then                          -- the track's own modulators, beside its strip
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local tw = D.modpanes_w(tr, "TRACK")
    r.ImGui_PushID(ctx, "trackmods")
    r.ImGui_DrawList_AddRectFilled(dl, x + 3, y, x + tw + 5, y + h, C.dev, 6)
    D.modpanes(tr, "TRACK", x + 4, y, h, dl)
    r.ImGui_DrawList_AddRect(dl, x + 3, y, x + tw + 5, y + h, C.dev_edge, 6, 0, 1.5)
    r.ImGui_PopID(ctx)
    x = x + tw + 6
  end
  local n = r.TrackFX_GetCount(tr)
  for i = 0, n - 1 do
    local fg = r.TrackFX_GetFXGUID(tr, i)
    if not S.lfo_owner[fg] and not S.hidden[fg] then
      D.plus(i, x, y, h)
      x = x + GAP
      x = x + D.device(tr, i, x, y, h)
    end
  end
  D.plus(n, x, y, h)
  x = x + GAP
  S.row_w = x - x0
  r.ImGui_SetCursorScreenPos(ctx, x0, y)
  r.ImGui_Dummy(ctx, x - x0, h + MARGIN)
end

---------------------------------------------------------------- the window
function D.empty(text)
  local w, h = r.ImGui_GetContentRegionAvail(ctx)
  local tw, th = r.ImGui_CalcTextSize(ctx, text)
  local x, y = r.ImGui_GetCursorPos(ctx)
  r.ImGui_SetCursorPos(ctx, x + math.max(0, (w - tw) / 2), y + math.max(0, (h - th) / 2))
  U.text_col(C.label, text)
end

local STYLE = {
  { r.ImGui_Col_WindowBg, C.bg }, { r.ImGui_Col_ChildBg, 0x00000000 }, { r.ImGui_Col_Text, C.text },
  { r.ImGui_Col_Border, C.line }, { r.ImGui_Col_FrameBg, C.field }, { r.ImGui_Col_FrameBgHovered, 0x1A1A1AFF },
  { r.ImGui_Col_FrameBgActive, 0x222222FF }, { r.ImGui_Col_Header, 0x3E1A04FF },
  { r.ImGui_Col_HeaderHovered, 0x2A2A2AFF }, { r.ImGui_Col_HeaderActive, 0x333333FF },
  { r.ImGui_Col_PopupBg, C.field }, { r.ImGui_Col_TextSelectedBg, 0x56220299 },
  { r.ImGui_Col_ScrollbarBg, 0x0E0E0EFF }, { r.ImGui_Col_ScrollbarGrab, 0x2E2E2EFF },
  { r.ImGui_Col_ScrollbarGrabHovered, 0x3A3A3AFF }, { r.ImGui_Col_ScrollbarGrabActive, C.accent },
  { r.ImGui_Col_ResizeGrip, 0x00000000 }, { r.ImGui_Col_Separator, C.line },
  { r.ImGui_Col_NavHighlight or r.ImGui_Col_NavCursor, C.accent },
  { r.ImGui_Col_TitleBg, 0x1A1A1AFF }, { r.ImGui_Col_TitleBgActive, 0x262626FF },
  { r.ImGui_Col_TitleBgCollapsed, 0x1A1A1AFF },
}
for i = #STYLE, 1, -1 do
  if not STYLE[i][1] then table.remove(STYLE, i) end
end

local function frame()
  local tr = F.track()
  if tr ~= S.track then
    S.track, S.guid, S.learn = tr, nil, nil
    S.scan_count, S.scan_t = -1, 0
  end
  if not tr then
    U.head("DEVICES")
    D.empty("No track selected")
    return
  end
  F.scan(tr, false)
  RC.poll(tr)
  D.touch_poll(tr)
  if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape(), false) then
    S.learn, S.route, S.route_out, S.route_src = nil, nil, nil, nil
  end
  -- routing stays on across tracks (global modulation): on the source's track the modulator
  -- itself, elsewhere the Global that already carries it (or none yet: the first click makes it)
  if S.route_src then
    if r.GetTrackGUID(tr) == S.route_src.track then
      S.route, S.route_out = S.route_src.lg, S.route_src.out
    else
      local n = M.gslot(S.route_src.track, S.route_src.lg, S.route_src.out)
      local ri = n and M.find_slot_fx(tr, "grecv", n)
      S.route, S.route_out = ri and r.TrackFX_GetFXGUID(tr, ri) or nil, nil
    end
  elseif S.route and not F.index(tr, S.route) then
    S.route = nil
  end
  if not F.index(tr, S.guid) and r.TrackFX_GetCount(tr) > 0 then S.guid = r.TrackFX_GetFXGUID(tr, 0) end
  local _, tname = r.GetTrackName(tr)
  U.head((S.route or S.route_src) and ("ROUTING" .. (S.route_src and (" " .. (S.route_src.label or "")) or "")
      .. "  -  click a parameter and drag for the amount; another track works too (Esc ends)")
    or S.learn and "LEARN  -  move a parameter in the plugin's window, or click one in the list (Esc stops)"
    or ("DEVICES  -  " .. math.floor(r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")) .. ": " .. tname))
  if r.ImGui_BeginChild(ctx, "##row", 0, 0, 0, r.ImGui_WindowFlags_HorizontalScrollbar()) then
    D.row(tr)
    r.ImGui_EndChild(ctx)
  end
end

local function loop()
  r.ImGui_PushFont(ctx, font, 13)
  for _, c in ipairs(STYLE) do r.ImGui_PushStyleColor(ctx, c[1](), c[2]) end
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 6, 3)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 2)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 4, 2)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ScrollbarSize(), 8)
  r.ImGui_SetNextWindowSize(ctx, 1200, 300, r.ImGui_Cond_FirstUseEver())
  if S.dock_to then
    r.ImGui_SetNextWindowDockID(ctx, S.dock_to)
    S.dock_to = nil
  end
  local flags = r.ImGui_WindowFlags_NoCollapse() | r.ImGui_WindowFlags_NoTitleBar()
    | r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
  local visible, open = r.ImGui_Begin(ctx, "Devices", true, flags)
  if visible then
    frame()
    H.run_later()
    r.ImGui_End(ctx)
  end
  D.kt_window()
  if S.close then open = false end
  r.ImGui_PopStyleVar(ctx, 4)
  r.ImGui_PopStyleColor(ctx, #STYLE)
  r.ImGui_PopFont(ctx)
  if open then r.defer(loop) end
end

RC.load()
r.atexit(function()
  if cmd_id and cmd_id ~= 0 then
    r.SetToggleCommandState(section_id, cmd_id, 0)
    r.RefreshToolbar2(section_id, cmd_id)
  end
end)
r.defer(loop)
