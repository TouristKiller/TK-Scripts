local M = {}

M.version = 19
M.filename = "TK_Kit_Maker_Sequencer.jsfx"
M.add_name = "TK_Kit_Maker_Sequencer"

M.source = [==[desc:TK Kit Maker Sequencer
//author: TouristKiller
//tags: MIDI sequencer generator
// Sample-accurate step sequencer engine for TK Kit Maker.
// Reads its pattern from shared memory (gmem) written by the Lua UI and
// emits MIDI note-ons/offs in the audio thread for rock-solid timing.
// TK_ENGINE_VERSION:19
// One instance runs on a dedicated MIDI bus track that routes MIDI (via
// MIDI-only sends) to every RS5k lane track. It plays all lanes at once;
// each RS5k filters to its own note. Reads the pattern from gmem.
slider1:0<0,100000000,1>OwnerID
options:gmem=TKKitMakerSeq

@init
G_EPOCH=0; G_RUN=1; G_SYNC=2; G_TEMPO=3; G_TOTAL=4; G_SOLO=5; G_RESTART=6; G_NLANES=7; G_BASE=8; G_ACTIVE=9;
G_AUD_TARGET=10; G_AUD_NOTE=11; G_AUD_VEL=12; G_AUD_GATE=13; G_AUD_OBEY=14; G_AUD_TOKEN=15; G_AUD_CH=19;
G_ALIVE=16; G_PH=17; G_NOTES=18; G_LANEPH=32;
LANE_BASE=128; LANE_STRIDE=128;
L_CYCLE=0; L_SPEED=1; L_SOLO=2; L_MODE=3; L_RETRIG=4; L_NOTE=5; L_OBEY=6; L_DIRECTION=7;
L_ECHO_ON=8; L_ECHO_COUNT=9; L_ECHO_MODE=10; L_ECHO_STEP=11; L_ECHO_RATE=12;
L_LOOP_LEN=13; L_LOOP_MASK=14;
L_ON=16; L_VEL=32; L_GATE=48; L_LEN=64; L_SUB=80; L_PROB=96; L_PITCH=112;

clk_time=1024; clk_step=1088; act_note=1152; act_off=1216;
sub_rem=1280; sub_next=1344; sub_per=1408; sub_note=1472; sub_vel=1536; sub_off=1600; disp_step=1664; sub_pitch=1728;
echo_active=1792; echo_time=2048; echo_note=2304; echo_vel=2560; echo_off=2816;
ECHO_SLOTS=16;

prev_active=0; prev_restart=-1; prev_aud_token=-1; cur_time=0; last_block_end=-1; owner_id=slider1|0; aud_note=0; aud_off=0; aud_ch=0;
i=0;
loop(16,
  clk_time[i]=0; clk_step[i]=1; act_note[i]=0; act_off[i]=0; sub_rem[i]=0; disp_step[i]=0;
  sub_pitch[i]=0;
  i+=1;
);
i=0;
loop(256,
  echo_active[i]=0; echo_time[i]=0; echo_note[i]=0; echo_vel[i]=0; echo_off[i]=0;
  i+=1;
);

@slider
owner_id=slider1|0;

@block
gmem[G_ALIVE] = gmem[G_ALIVE] + 1;
mrecv_ofs=0;
while(midirecv(mrecv_ofs, mrecv_a, mrecv_b, mrecv_c)) (
  midisend(mrecv_ofs, mrecv_a, mrecv_b, mrecv_c);
);

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
active_target = gmem[G_ACTIVE]|0;
aud_target = gmem[G_AUD_TARGET]|0;
seq_owned = (owner_id > 0) && (active_target == owner_id);

(restart != prev_restart) ? cur_time=0;

sync==1 ? (
  active = seq_owned && (play_state & 1) ? 1 : 0;
  t0 = (play_state & 1) ? (beat_position*(60/use_tempo)) : 0;
) : (
  active = seq_owned && gmem[G_RUN]>=0.5 ? 1 : 0;
  t0 = active ? cur_time : 0;
);

resync=0;
(active && !prev_active) ? resync=1;
(restart != prev_restart) ? resync=1;
(sync==1 && active && prev_active && abs(t0-last_block_end) > (blockdur*4+0.02)) ? resync=1;

t1 = t0 + blockdur;

(aud_note>0 && aud_off>0 && aud_off<t1) ? (
  off_aud=aud_off-t0; off_aud<0 ? off_aud=0;
  so_aud=floor(off_aud*sr); so_aud>=blocklen ? so_aud=blocklen-1;
  midisend(so_aud,0x80,aud_note,0);
  aud_note=0; aud_off=0;
);

(owner_id > 0 && aud_target == owner_id && gmem[G_AUD_TOKEN] != prev_aud_token) ? (
  cmd_note=gmem[G_AUD_NOTE]|0;
  cmd_vel=gmem[G_AUD_VEL]|0;
  cmd_gate=gmem[G_AUD_GATE]; cmd_gate<0 ? cmd_gate=0;
  cmd_obey=gmem[G_AUD_OBEY]>=0.5;
  cmd_ch=gmem[G_AUD_CH]|0; cmd_ch<0 ? cmd_ch=0; cmd_ch>15 ? cmd_ch=15;
  aud_note>0 ? (midisend(0,0x80,aud_note,0); aud_note=0; aud_off=0;);
  (cmd_note>=0 && cmd_note<=127 && cmd_vel>0) ? (
    cmd_vel>127 ? cmd_vel=127;
    midisend(0,0x90,cmd_note,cmd_vel);
    aud_note=cmd_note;
    aud_ch=cmd_ch;
    aud_off=cmd_obey ? (t0 + cmd_gate) : 0;
  );
  prev_aud_token=gmem[G_AUD_TOKEN];
);

active ? (
  resync ? (
    i=0;
    loop(nlanes,
      act_note[i]>0 ? (midisend(0,0x80,act_note[i],0); act_note[i]=0;);
      act_off[i]=0; sub_rem[i]=0;
      es=0;
      while(es<ECHO_SLOTS) (
        ei=i*ECHO_SLOTS+es;
        echo_active[ei]=0;
        es+=1;
      );
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
      clk_step[i]=k;
      dir=gmem[LB+L_DIRECTION]|0;
      dir==1 ? (
        disp_step[i]=cyc-(k%cyc);
      ) : dir==2 && cyc>1 ? (
        pend=((cyc*2)-2)>0 ? (k%((cyc*2)-2)) : 0;
        disp_step[i]=(pend<cyc) ? (pend+1) : (((cyc*2)-2)-pend+1);
      ) : (
        disp_step[i]=(k%cyc)+1;
      );
      i+=1;
    );
  );

  i=0;
  loop(nlanes,
    LB=LANE_BASE+i*LANE_STRIDE;
    cyc=gmem[LB+L_CYCLE]|0; cyc<1 ? cyc=1;
    spd=gmem[LB+L_SPEED]; spd<=0 ? spd=1;
    lane_period=cycle_dur/(cyc*spd); lane_period<=0 ? lane_period=step_dur;
    dir=gmem[LB+L_DIRECTION]|0;
    mode=gmem[LB+L_MODE]|0;
    obey=gmem[LB+L_OBEY]>=0.5;
    note=gmem[LB+L_NOTE]|0; note<0 ? note=0; note>127 ? note=127;
    lane_solo=gmem[LB+L_SOLO]>=0.5;
    loop_len=gmem[LB+L_LOOP_LEN]|0; loop_len<1 ? loop_len=1; loop_len>8 ? loop_len=8;
    loop_mask=gmem[LB+L_LOOP_MASK]|0;
    muted=(any_solo>=0.5 && !lane_solo) ? 1 : 0;

    (act_note[i]>0 && act_off[i]>0 && act_off[i]<t1) ? (
      off=act_off[i]-t0; off<0 ? off=0;
      so=floor(off*sr); so>=blocklen ? so=blocklen-1;
      midisend(so,0x80,act_note[i],0);
      act_note[i]=0; act_off[i]=0;
    );

    guard=0;
    while(guard<64) (
      min_idx=-1;
      min_t=t1+1;
      es=0;
      while(es<ECHO_SLOTS) (
        ei=i*ECHO_SLOTS+es;
        (echo_active[ei]>=0.5 && echo_time[ei]<t1 && echo_time[ei]<min_t) ? (
          min_t=echo_time[ei];
          min_idx=ei;
        );
        es+=1;
      );
      min_idx<0 ? (
        guard=64;
      ) : (
        e_note=echo_note[min_idx]|0; e_note<0 ? e_note=0; e_note>127 ? e_note=127;
        e_vel=echo_vel[min_idx]|0; e_vel<1 ? e_vel=1; e_vel>127 ? e_vel=127;
        offe=min_t-t0; offe<0 ? offe=0;
        se=floor(offe*sr); se>=blocklen ? se=blocklen-1;
        !muted ? (
          act_note[i]>0 ? midisend(se,0x80,act_note[i],0);
          midisend(se,0x90,e_note,e_vel);
          gmem[G_NOTES]=gmem[G_NOTES]+1;
          act_note[i]=e_note;
          act_off[i]=(mode==1 && obey && echo_off[min_idx]>0) ? echo_off[min_idx] : 0;
        );
        echo_active[min_idx]=0;
        guard+=1;
      );
    );

    guard=0;
    while(sub_rem[i]>0 && sub_next[i]<t1 && guard<64) (
      lane_ch=i;
      pitch_off=sub_pitch[i]|0;
      note_ch=note+pitch_off; note_ch<0 ? note_ch=0; note_ch>127 ? note_ch=127;
      so2=sub_next[i]-t0; so2<0 ? so2=0;
      ss=floor(so2*sr); ss>=blocklen ? ss=blocklen-1;
      !muted ? (
        act_note[i]>0 ? midisend(ss,0x80,act_note[i],0);
        midisend(ss,0x90,note_ch,sub_vel[i]);
        gmem[G_NOTES]=gmem[G_NOTES]+1;
        act_note[i]=note_ch;
        act_off[i]=(mode==1 && obey) ? sub_next[i]+sub_off[i] : 0;
      );
      sub_next[i]+=sub_per[i];
      sub_rem[i]-=1;
      guard+=1;
    );

    guard=0;
    while(clk_time[i]<t1 && guard<256) (
      et=clk_time[i];
      tick=clk_step[i]|0;
      dir==1 ? (
        st=cyc-(tick%cyc);
      ) : dir==2 && cyc>1 ? (
        pend=((cyc*2)-2)>0 ? (tick%((cyc*2)-2)) : 0;
        st=(pend<cyc) ? (pend+1) : (((cyc*2)-2)-pend+1);
      ) : (
        st=(tick%cyc)+1;
      );
      cycle_idx=floor(tick/cyc);
      slot=cycle_idx%loop_len;
      allow=(loop_mask&(1<<slot))!=0;
      on=(gmem[LB+L_ON+(st-1)]>=0.5) && allow;
      disp_step[i]=st;
      (on && !muted) ? (
        prob=gmem[LB+L_PROB+(st-1)]|0; prob<0 ? prob=0; prob>100 ? prob=100;
        chance_ok=(prob>=100) || (prob>0 && rand(100)<prob);
        chance_ok ? (
          vel=gmem[LB+L_VEL+(st-1)]|0; vel<1 ? vel=1; vel>127 ? vel=127;
          gate=gmem[LB+L_GATE+(st-1)]; gate<1 ? gate=1; gate>100 ? gate=100;
          len=gmem[LB+L_LEN+(st-1)]|0; len<1 ? len=1;
          pitch_off=gmem[LB+L_PITCH+(st-1)]|0;
          note_ch=note+pitch_off; note_ch<0 ? note_ch=0; note_ch>127 ? note_ch=127;
          subs=gmem[LB+L_SUB+(st-1)]|0; subs<1 ? subs=1; subs>8 ? subs=8;
          length_time=len*step_dur;
          sp=lane_period/subs; sp<=0 ? sp=step_dur;
          gate_time=(subs>1) ? (sp*(gate/100)) : (length_time*(gate/100));
          gate_time<=0 ? gate_time=step_dur*0.5;
          off=et-t0; off<0 ? off=0;
          so=floor(off*sr); so>=blocklen ? so=blocklen-1;
          lane_ch=i;
          act_note[i]>0 ? (midisend(so,0x80,act_note[i],0); act_note[i]=0;);
          midisend(so,0x90,note_ch,vel);
          gmem[G_NOTES]=gmem[G_NOTES]+1;
          act_note[i]=note_ch;
          act_off[i]=(mode==1 && obey) ? et+gate_time : 0;
          echo_on=gmem[LB+L_ECHO_ON]>=0.5;
          echo_count=gmem[LB+L_ECHO_COUNT]|0; echo_count<1 ? echo_count=1; echo_count>4 ? echo_count=4;
          echo_mode=gmem[LB+L_ECHO_MODE]|0;
          echo_step=gmem[LB+L_ECHO_STEP]|0; echo_step<1 ? echo_step=1; echo_step>32 ? echo_step=32;
          echo_rate=gmem[LB+L_ECHO_RATE]|0;
          echo_period=step_dur;
          echo_rate==0 ? echo_period=step_dur*4;
          echo_rate==1 ? echo_period=step_dur*(8/3);
          echo_rate==2 ? echo_period=step_dur*2;
          echo_rate==3 ? echo_period=step_dur*(4/3);
          echo_rate==5 ? echo_period=step_dur*(2/3);
          echo_rate==6 ? echo_period=step_dur*0.5;
          echo_rate==7 ? echo_period=step_dur*(1/3);
          echo_on ? (
            eidx=1;
            while(eidx<=echo_count) (
              e_t=et+(eidx*echo_period);
              e_vel=vel;
              echo_mode==1 ? e_vel+=eidx*echo_step;
              echo_mode==2 ? e_vel-=eidx*echo_step;
              e_vel<1 ? e_vel=1; e_vel>127 ? e_vel=127;
              e_off=(mode==1 && obey) ? e_t+gate_time : 0;

              slot_pick=-1;
              es=0;
              while(es<ECHO_SLOTS) (
                ei=i*ECHO_SLOTS+es;
                (slot_pick<0 && echo_active[ei]<0.5) ? slot_pick=ei;
                es+=1;
              );
              slot_pick<0 ? (
                oldest_t=echo_time[i*ECHO_SLOTS];
                oldest_idx=i*ECHO_SLOTS;
                es=1;
                while(es<ECHO_SLOTS) (
                  ei=i*ECHO_SLOTS+es;
                  echo_time[ei]<oldest_t ? (
                    oldest_t=echo_time[ei];
                    oldest_idx=ei;
                  );
                  es+=1;
                );
                slot_pick=oldest_idx;
              );

              echo_active[slot_pick]=1;
              echo_time[slot_pick]=e_t;
              echo_note[slot_pick]=note_ch;
              echo_vel[slot_pick]=e_vel;
              echo_off[slot_pick]=e_off;
              eidx+=1;
            );
          );
          subs>1 ? (
            sub_rem[i]=subs-1; sub_next[i]=et+sp; sub_per[i]=sp;
            sub_note[i]=note_ch; sub_vel[i]=vel; sub_off[i]=gate_time;
            sub_pitch[i]=pitch_off;
          ) : ( sub_rem[i]=0; );
        ) : (
          sub_rem[i]=0;
        );
      );
      clk_time[i]+=lane_period;
      clk_step[i]=tick+1;
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
      es=0;
      while(es<ECHO_SLOTS) (
        ei=i*ECHO_SLOTS+es;
        echo_active[ei]=0;
        es+=1;
      );
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
