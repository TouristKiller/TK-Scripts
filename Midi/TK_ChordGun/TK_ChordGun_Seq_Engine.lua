-- @noindex
-- Sequencer engine for TK ChordGun.
--
-- The JSFX source lives here as a string and is written into REAPER/Effects on
-- demand, the same way TK Kit Maker ships its sequencer. That keeps the engine
-- and this script locked to one another: ensure_installed() rewrites the file
-- whenever the TK_CG_ENGINE_VERSION marker does not match M.version, so a Lua
-- side that writes a new gmem layout can never end up talking to an old engine.
--
-- Unlike TK_Scale_Filter.jsfx this one goes in the NORMAL track FX chain, above
-- the instrument -- not in the Input FX chain. Input FX only run on a
-- record-armed track; normal track FX run whenever the audio engine does, which
-- is what lets the progression play without arming anything.
--
local M = {}

M.version = 1
M.filename = "TK_ChordGun_Sequencer.jsfx"
M.add_name = "TK_ChordGun_Sequencer"
M.gmem_name = "TK_ChordGun_Filter"

-- Shared gmem block with TK_Scale_Filter, which owns 0..159. Everything from
-- 160 up is ours, so ChordGun keeps a single gmem_attach instead of switching
-- namespaces every frame.
M.GMEM = {
  RUN        = 160,  -- 1 = free-running playback
  SYNC       = 161,  -- 1 = follow the REAPER transport instead
  TEMPO      = 162,  -- BPM from Lua; 0 = use the host tempo
  NSLOTS     = 163,  -- how many slots the cycle covers
  RESTART    = 164,  -- bump to force the engine back to the top
  ACTIVE     = 165,  -- OwnerID currently allowed to play
  ALIVE      = 166,  -- engine heartbeat, so Lua can tell it is loaded
  CHAN       = 167,  -- MIDI channel, 0-15
  CURSTEP    = 168,  -- engine -> Lua: slot being played, 1-based (0 = none)
  CURREP     = 169,  -- engine -> Lua: repeat index within that slot, 0-based
  PANIC      = 170,  -- bump to kill every sounding note
  VER        = 171,  -- engine -> Lua: version of the loaded JSFX
  AUD_TOKEN  = 172,  -- bump to play the audition chord below
  AUD_N      = 173,  -- how many notes that chord has
  AUD_GATE   = 174,  -- audition gate in seconds; 0 = hold until PANIC
  AUD_NOTE   = 176,  -- 176..187
  AUD_VEL    = 188,  -- 188..199

  SLOT_BASE   = 256,
  SLOT_STRIDE = 64,
  MAX_SLOTS   = 16,
  MAX_NOTES   = 12,

  -- Offsets within a slot block.
  S_BEATS   = 0,   -- length of one pass through this slot, in beats
  S_REPEATS = 1,
  S_NNOTES  = 2,
  S_NOTE    = 4,   -- +4 .. +15
  S_VEL     = 16,  -- +16 .. +27
  S_ONSET   = 28,  -- +28 .. +39, offset from the slot start in beats
  S_GATE    = 40,  -- +40 .. +51, note length in beats
}

M.source = [==[desc:TK ChordGun Sequencer
//author: TouristKiller
//tags: MIDI sequencer generator chords
// Sample-accurate progression player for TK ChordGun.
// TK_CG_ENGINE_VERSION:1
//
// Belongs in the normal track FX chain, ABOVE the instrument -- its MIDI
// reaches the instrument by flowing down the chain. In the Input FX chain it
// would only run while the track is record-armed, which is the whole thing
// this engine exists to avoid.
//
// Deliberately dumb: it makes no musical decisions at all. Lua hands it, per
// slot, a set of notes each carrying its own velocity, onset and gate, so
// strum, arpeggios and velocity curves stay in the Lua code that already
// implements them. All this does is put those notes on the right sample.
slider1:0<0,100000000,1>OwnerID
options:gmem=TK_ChordGun_Filter

@init
G_RUN=160; G_SYNC=161; G_TEMPO=162; G_NSLOTS=163; G_RESTART=164; G_ACTIVE=165;
G_ALIVE=166; G_CHAN=167; G_CURSTEP=168; G_CURREP=169; G_PANIC=170; G_VER=171;
G_AUD_TOKEN=172; G_AUD_N=173; G_AUD_GATE=174; G_AUD_NOTE=176; G_AUD_VEL=188;
SLOT_BASE=256; SLOT_STRIDE=64;
S_BEATS=0; S_REPEATS=1; S_NNOTES=2; S_NOTE=4; S_VEL=16; S_ONSET=28; S_GATE=40;
MAXSLOTS=16; MAXNOTES=12;
ENGINE_VERSION=1;

// Two queues. Scheduled note-ons wait in the first until their sample lands in
// the current block; emitting one moves a note-off into the second. A queue
// rather than a single "currently playing chord" because a strummed or
// arpeggiated slot spreads its notes over time and can straddle a block edge.
QN=64;
pon_time=0; pon_note=64; pon_vel=128; pon_gate=192; pon_used=256;
poff_time=320; poff_note=384; poff_ch=448; poff_used=512;

i=0;
loop(QN,
  pon_used[i]=0; poff_used[i]=0;
  i+=1;
);

cur_time=0; ev_time=0; cur_slot=0; cur_rep=0;
prev_active=0; prev_restart=-1; prev_panic=-1; prev_aud_token=-1;
last_block_end=-1;

@slider
owner_id=slider1|0;

@block
gmem[G_ALIVE]=gmem[G_ALIVE]+1;
gmem[G_VER]=ENGINE_VERSION;

// Everything upstream passes through untouched -- items, input, other FX.
mrecv_ofs=0;
while(midirecv(mrecv_ofs, mrecv_a, mrecv_b, mrecv_c)) (
  midisend(mrecv_ofs, mrecv_a, mrecv_b, mrecv_c);
);

owner_id=slider1|0;
nslots=gmem[G_NSLOTS]|0; nslots<1 ? nslots=1; nslots>MAXSLOTS ? nslots=MAXSLOTS;
sync=gmem[G_SYNC]|0;
ch=gmem[G_CHAN]|0; ch<0 ? ch=0; ch>15 ? ch=15;
lua_tempo=gmem[G_TEMPO];
use_tempo=lua_tempo>0 ? lua_tempo : tempo;
use_tempo<=0 ? use_tempo=120;
spb=60/use_tempo;
sr=srate; sr<=0 ? sr=48000;
blocklen=samplesblock;
blockdur=blocklen/sr;
restart=gmem[G_RESTART];
panic=gmem[G_PANIC];
active_target=gmem[G_ACTIVE]|0;
seq_owned=(owner_id>0) && (active_target==owner_id);

sync==1 ? (
  active = seq_owned && (play_state & 1) ? 1 : 0;
  t0 = (play_state & 1) ? (beat_position*spb) : 0;
) : (
  active = seq_owned && gmem[G_RUN]>=0.5 ? 1 : 0;
  t0 = active ? cur_time : 0;
);
t1 = t0 + blockdur;

// A panic clears both queues and shuts the channel up. Also the way back from
// a stuck note, so it kills whatever is sounding rather than only what we know
// about.
(panic != prev_panic) ? (
  q=0;
  loop(QN,
    poff_used[q]>=0.5 ? (midisend(0,0x80+poff_ch[q],poff_note[q],0); poff_used[q]=0;);
    pon_used[q]=0;
    q+=1;
  );
  midisend(0,0xB0+ch,123,0);
  prev_panic=panic;
);

// Audition: single chords fired from the UI (preview, Alt+Click, MIDI trigger)
// come through here too, so they are as tight as the progression and equally
// free of the record-arm requirement.
(seq_owned && gmem[G_AUD_TOKEN] != prev_aud_token) ? (
  aud_n=gmem[G_AUD_N]|0; aud_n<0 ? aud_n=0; aud_n>MAXNOTES ? aud_n=MAXNOTES;
  aud_gate=gmem[G_AUD_GATE];
  k=0;
  loop(aud_n,
    an=gmem[G_AUD_NOTE+k]|0;
    av=gmem[G_AUD_VEL+k]|0;
    (an>=0 && an<=127 && av>0) ? (
      av>127 ? av=127;
      midisend(0,0x90+ch,an,av);
      aud_gate>0 ? (
        oi=-1; o=0;
        while(o<QN && oi<0) (poff_used[o]<0.5 ? oi=o; o+=1;);
        oi>=0 ? (
          poff_used[oi]=1; poff_time[oi]=t0+aud_gate; poff_note[oi]=an; poff_ch[oi]=ch;
        );
      );
    );
    k+=1;
  );
  prev_aud_token=gmem[G_AUD_TOKEN];
);

// One pass through the progression, in seconds. Slots can differ in length, so
// this is a sum rather than a step count.
cycle_dur=0;
i=0;
loop(nslots,
  SB=SLOT_BASE+i*SLOT_STRIDE;
  cb=gmem[SB+S_BEATS]; cb<=0 ? cb=1;
  crp=gmem[SB+S_REPEATS]|0; crp<1 ? crp=1;
  cycle_dur += cb*crp*spb;
  i+=1;
);
cycle_dur<=0 ? cycle_dur=spb;

resync=0;
(active && !prev_active) ? resync=1;
(restart != prev_restart) ? resync=1;
// A transport jump lands somewhere else entirely; anything more than a few
// blocks away is a relocate, not drift.
(sync==1 && active && prev_active && abs(t0-last_block_end) > (blockdur*4+0.02)) ? resync=1;

active ? (
  resync ? (
    q=0;
    loop(QN, pon_used[q]=0; q+=1;);
    // Walk the cycle to find which slot and repeat t0 falls inside, so that
    // starting mid-bar (or scrubbing the transport) lands on the right chord
    // instead of restarting the progression.
    ncyc=floor(t0/cycle_dur);
    pos=t0-ncyc*cycle_dur;
    acc=0; cs=0; cr=0; found=0;
    i=0;
    while(i<nslots && !found) (
      SB=SLOT_BASE+i*SLOT_STRIDE;
      cb=gmem[SB+S_BEATS]; cb<=0 ? cb=1;
      crp=gmem[SB+S_REPEATS]|0; crp<1 ? crp=1;
      j=0;
      while(j<crp && !found) (
        d=cb*spb;
        pos < acc+d-0.0000001 ? (cs=i; cr=j; found=1;) : (acc+=d;);
        j+=1;
      );
      i+=1;
    );
    found ? (ev_time=ncyc*cycle_dur+acc;) : (ev_time=ncyc*cycle_dur+cycle_dur; cs=0; cr=0;);
    cur_slot=cs; cur_rep=cr;
  );

  // Queue every slot that starts inside this block. The guard is a runaway
  // stop for a pathological cycle_dur, not an expected limit.
  guard=0;
  while(ev_time < t1 && guard<32) (
    SB=SLOT_BASE+cur_slot*SLOT_STRIDE;
    sb_beats=gmem[SB+S_BEATS]; sb_beats<=0 ? sb_beats=1;
    sb_rep=gmem[SB+S_REPEATS]|0; sb_rep<1 ? sb_rep=1;
    nn=gmem[SB+S_NNOTES]|0; nn<0 ? nn=0; nn>MAXNOTES ? nn=MAXNOTES;
    k=0;
    loop(nn,
      n=gmem[SB+S_NOTE+k]|0;
      v=gmem[SB+S_VEL+k]|0;
      ons=gmem[SB+S_ONSET+k]; ons<0 ? ons=0;
      gt=gmem[SB+S_GATE+k]; gt<=0 ? gt=sb_beats;
      (n>=0 && n<=127 && v>0) ? (
        v>127 ? v=127;
        qi=-1; q=0;
        while(q<QN && qi<0) (pon_used[q]<0.5 ? qi=q; q+=1;);
        qi>=0 ? (
          pon_used[qi]=1;
          pon_time[qi]=ev_time+ons*spb;
          pon_note[qi]=n;
          pon_vel[qi]=v;
          pon_gate[qi]=gt*spb;
        );
      );
      k+=1;
    );
    gmem[G_CURSTEP]=cur_slot+1;
    gmem[G_CURREP]=cur_rep;
    ev_time += sb_beats*spb;
    cur_rep+=1;
    cur_rep>=sb_rep ? (
      cur_rep=0;
      cur_slot+=1;
      cur_slot>=nslots ? cur_slot=0;
    );
    guard+=1;
  );

  sync==0 ? cur_time=t1;
  last_block_end=t1;
) : (
  prev_active ? (
    q=0;
    loop(QN,
      poff_used[q]>=0.5 ? (midisend(0,0x80+poff_ch[q],poff_note[q],0); poff_used[q]=0;);
      pon_used[q]=0;
      q+=1;
    );
    gmem[G_CURSTEP]=0;
    gmem[G_CURREP]=0;
  );
  sync==0 ? cur_time=0;
);

// Offs before ons, so a chord that ends exactly where the next one starts
// releases first instead of being cut off by its own successor.
q=0;
loop(QN,
  (poff_used[q]>=0.5 && poff_time[q]<t1) ? (
    off=poff_time[q]-t0; off<0 ? off=0;
    so=floor(off*sr); so>=blocklen ? so=blocklen-1; so<0 ? so=0;
    midisend(so,0x80+poff_ch[q],poff_note[q],0);
    poff_used[q]=0;
  );
  q+=1;
);

q=0;
loop(QN,
  (pon_used[q]>=0.5 && pon_time[q]<t1) ? (
    off=pon_time[q]-t0; off<0 ? off=0;
    so=floor(off*sr); so>=blocklen ? so=blocklen-1; so<0 ? so=0;
    midisend(so,0x90+ch,pon_note[q],pon_vel[q]);
    oi=-1; o=0;
    while(o<QN && oi<0) (poff_used[o]<0.5 ? oi=o; o+=1;);
    oi>=0 ? (
      poff_used[oi]=1;
      poff_time[oi]=pon_time[q]+pon_gate[q];
      poff_note[oi]=pon_note[q];
      poff_ch[oi]=ch;
    );
    pon_used[q]=0;
  );
  q+=1;
);

// Second sweep for gates short enough to open and close inside one block.
q=0;
loop(QN,
  (poff_used[q]>=0.5 && poff_time[q]<t1) ? (
    off=poff_time[q]-t0; off<0 ? off=0;
    so=floor(off*sr); so>=blocklen ? so=blocklen-1; so<0 ? so=0;
    midisend(so,0x80+poff_ch[q],poff_note[q],0);
    poff_used[q]=0;
  );
  q+=1;
);

prev_active=active;
prev_restart=restart;
]==]

-- Writes the engine into REAPER/Effects unless a matching version is already
-- there. Returns true if the file is present and current.
function M.ensure_installed()
  local res = reaper.GetResourcePath and reaper.GetResourcePath() or nil
  if not res then return false end

  local path = res .. "/Effects/" .. M.filename
  local marker = "TK_CG_ENGINE_VERSION:" .. tostring(M.version)

  local existing = io.open(path, "rb")
  if existing then
    local content = existing:read("*a") or ""
    existing:close()
    if content:find(marker, 1, true) then
      return true
    end
  end

  local f = io.open(path, "wb")
  if not f then return false end
  f:write(M.source)
  f:close()
  return true
end

return M
