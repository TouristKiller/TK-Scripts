local M = {}

M.version = 8
M.filename = "TK_Kit_Maker_Sequencer.jsfx"
M.add_name = "TK_Kit_Maker_Sequencer"

M.source = [==[desc:TK Kit Maker Sequencer
//author: TouristKiller
//tags: MIDI sequencer generator
// Sample-accurate step sequencer engine for TK Kit Maker.
// Reads its pattern from shared memory (gmem) written by the Lua UI and
// emits MIDI note-ons/offs in the audio thread for rock-solid timing.
// TK_ENGINE_VERSION:8
// One instance runs on a dedicated MIDI bus track that routes MIDI (via
// MIDI-only sends) to every RS5k lane track. It plays all lanes at once;
// each RS5k filters to its own note. Reads the pattern from gmem.
options:gmem=TKKitMakerSeq

@init
G_EPOCH=0; G_RUN=1; G_SYNC=2; G_TEMPO=3; G_TOTAL=4; G_SOLO=5; G_RESTART=6; G_NLANES=7; G_BASE=8; G_ACTIVE=9;
G_ALIVE=16; G_PH=17; G_NOTES=18; G_LANEPH=32;
LANE_BASE=128; LANE_STRIDE=128;
L_CYCLE=0; L_SPEED=1; L_SOLO=2; L_MODE=3; L_RETRIG=4; L_NOTE=5; L_OBEY=6;
L_ON=16; L_VEL=32; L_GATE=48; L_LEN=64; L_SUB=80; L_PROB=96;

clk_time=1024; clk_step=1088; act_note=1152; act_off=1216;
sub_rem=1280; sub_next=1344; sub_per=1408; sub_note=1472; sub_vel=1536; sub_off=1600; disp_step=1664;

prev_active=0; prev_restart=-1; cur_time=0; last_block_end=-1;
i=0;
loop(16,
  clk_time[i]=0; clk_step[i]=1; act_note[i]=0; act_off[i]=0; sub_rem[i]=0; disp_step[i]=0;
  i+=1;
);

@block
gmem[G_ALIVE] = gmem[G_ALIVE] + 1;
// Drain incoming MIDI so any record-armed passthrough is not forwarded to
// the lane sends (would double-trigger pad previews).
mrecv_ofs=0;
while(midirecv(mrecv_ofs, mrecv_a, mrecv_b, mrecv_c)) ( mrecv_a=0; );

total = gmem[G_TOTAL]|0; total<1 ? total=16;
nlanes = gmem[G_NLANES]|0; nlanes<1 ? nlanes=1; nlanes>16 ? nlanes=16;
sync = gmem[G_SYNC]|0;
any_solo = gmem[G_SOLO];
lua_tempo = gmem[G_TEMPO];
use_tempo = lua_tempo>0 ? lua_tempo : tempo;
use_tempo<=0 ? use_tempo=120;
step_dur = (60/use_tempo)/4;
cycle_dur = total*step_dur;
sr = srate; sr<=0 ? sr=48000;
blocklen = samplesblock;
blockdur = blocklen/sr;
restart = gmem[G_RESTART];

sync==1 ? (
  active = (play_state & 1) ? 1 : 0;
  t0 = (play_state & 1) ? (beat_position*(60/use_tempo)) : 0;
) : (
  active = gmem[G_RUN]>=0.5 ? 1 : 0;
  t0 = active ? cur_time : 0;
);

resync=0;
(active && !prev_active) ? resync=1;
(restart != prev_restart) ? resync=1;
(sync==1 && active && prev_active && abs(t0-last_block_end) > (blockdur*4+0.02)) ? resync=1;

t1 = t0 + blockdur;

active ? (
  resync ? (
    i=0;
    loop(nlanes,
      act_note[i]>0 ? (midisend(0,0x80,act_note[i],0); act_note[i]=0;);
      act_off[i]=0; sub_rem[i]=0;
      i+=1;
    );
    i=0;
    loop(nlanes,
      LB=LANE_BASE+i*LANE_STRIDE;
      cyc=gmem[LB+L_CYCLE]|0; cyc<1 ? cyc=1;
      spd=gmem[LB+L_SPEED]; spd<=0 ? spd=1;
      lane_period=cycle_dur/(cyc*spd); lane_period<=0 ? lane_period=step_dur;
      k=floor(t0/lane_period);
      ct=k*lane_period;
      while(ct < t0-0.0000001) (ct+=lane_period; k+=1;);
      clk_time[i]=ct;
      clk_step[i]=(k%cyc)+1;
      disp_step[i]=((k+cyc-1)%cyc)+1;
      i+=1;
    );
  );

  i=0;
  loop(nlanes,
    LB=LANE_BASE+i*LANE_STRIDE;
    cyc=gmem[LB+L_CYCLE]|0; cyc<1 ? cyc=1;
    spd=gmem[LB+L_SPEED]; spd<=0 ? spd=1;
    lane_period=cycle_dur/(cyc*spd); lane_period<=0 ? lane_period=step_dur;
    mode=gmem[LB+L_MODE]|0;
    obey=gmem[LB+L_OBEY]>=0.5;
    note=gmem[LB+L_NOTE]|0; note<0 ? note=0; note>127 ? note=127;
    lane_solo=gmem[LB+L_SOLO]>=0.5;
    muted=(any_solo>=0.5 && !lane_solo) ? 1 : 0;

    (act_note[i]>0 && act_off[i]>0 && act_off[i]<t1) ? (
      off=act_off[i]-t0; off<0 ? off=0;
      so=floor(off*sr); so>=blocklen ? so=blocklen-1;
      midisend(so,0x80,act_note[i],0);
      act_note[i]=0; act_off[i]=0;
    );

    guard=0;
    while(sub_rem[i]>0 && sub_next[i]<t1 && guard<64) (
      so2=sub_next[i]-t0; so2<0 ? so2=0;
      ss=floor(so2*sr); ss>=blocklen ? ss=blocklen-1;
      !muted ? (
        act_note[i]>0 ? midisend(ss,0x80,act_note[i],0);
        midisend(ss,0x90,sub_note[i],sub_vel[i]);
        gmem[G_NOTES]=gmem[G_NOTES]+1;
        act_note[i]=sub_note[i];
        act_off[i]=(mode==1 && obey) ? sub_next[i]+sub_off[i] : 0;
      );
      sub_next[i]+=sub_per[i];
      sub_rem[i]-=1;
      guard+=1;
    );

    guard=0;
    while(clk_time[i]<t1 && guard<256) (
      et=clk_time[i];
      st=clk_step[i];
      on=gmem[LB+L_ON+(st-1)]>=0.5;
      disp_step[i]=st;
      (on && !muted) ? (
        prob=gmem[LB+L_PROB+(st-1)]|0; prob<0 ? prob=0; prob>100 ? prob=100;
        chance_ok=(prob>=100) || (prob>0 && rand(100)<prob);
        chance_ok ? (
          vel=gmem[LB+L_VEL+(st-1)]|0; vel<1 ? vel=1; vel>127 ? vel=127;
          gate=gmem[LB+L_GATE+(st-1)]; gate<1 ? gate=1; gate>100 ? gate=100;
          len=gmem[LB+L_LEN+(st-1)]|0; len<1 ? len=1;
          subs=gmem[LB+L_SUB+(st-1)]|0; subs<1 ? subs=1; subs>8 ? subs=8;
          length_time=len*step_dur;
          gate_time=length_time*(gate/100); gate_time<=0 ? gate_time=step_dur*0.5;
          sp=lane_period/subs; sp<=0 ? sp=step_dur;
          off=et-t0; off<0 ? off=0;
          so=floor(off*sr); so>=blocklen ? so=blocklen-1;
          act_note[i]>0 ? (midisend(so,0x80,act_note[i],0); act_note[i]=0;);
          midisend(so,0x90,note,vel);
          gmem[G_NOTES]=gmem[G_NOTES]+1;
          act_note[i]=note;
          act_off[i]=(mode==1 && obey) ? et+gate_time : 0;
          subs>1 ? (
            sub_rem[i]=subs-1; sub_next[i]=et+sp; sub_per[i]=sp;
            sub_note[i]=note; sub_vel[i]=vel; sub_off[i]=gate_time;
          ) : ( sub_rem[i]=0; );
        ) : (
          sub_rem[i]=0;
        );
      );
      clk_time[i]+=lane_period;
      clk_step[i]=(st%cyc)+1;
      guard+=1;
    );

    gmem[G_LANEPH+i]=disp_step[i];
    i+=1;
  );

  sync==0 ? cur_time=t1;
  last_block_end=t1;
  gmem[G_PH]=(floor(t0/step_dur)%total)+1;
) : (
  prev_active ? (
    i=0;
    loop(nlanes,
      act_note[i]>0 ? (midisend(0,0x80,act_note[i],0); act_note[i]=0;);
      sub_rem[i]=0;
      i+=1;
    );
  );
  sync==0 ? cur_time=0;
  gmem[G_PH]=0;
);

prev_active=active;
prev_restart=restart;
]==]

return M
