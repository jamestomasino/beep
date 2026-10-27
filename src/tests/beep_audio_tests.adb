with Ada.Exceptions;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Beep.Audio;
with Beep.Audio.Mixer;
with Beep.Audio.Shared;
with Beep.Config;
with Beep.Core.Types;
with Interfaces;

procedure Beep_Audio_Tests is
   use Ada.Text_IO;
   use Beep.Core.Types;
   use Beep.Audio.Mixer;
   use Interfaces;

   procedure Expect (Cond : Boolean; Msg : String) is
   begin
      if not Cond then
         raise Program_Error with Msg;
      end if;
   end Expect;

   function Default_Params return Mix_Parameters is
   begin
      return (Ambient_Drive => 0.32,
              Ambient_Max   => 0.30,
              Ambient_Decay => 0.992,
              Mid_Min       => 0.16,
              Mid_Max       => 0.52,
              Fore_Attn     => 0.55);
   end Default_Params;

   function Make_Event
     (Motif       : Motif_Type;
      Gain        : Float := 0.5;
      Duration_Ms : Integer := 100;
      Timestamp   : Milliseconds := 1000) return Sound_Event
   is
   begin
      return (Motif       => Motif,
              Gain        => Gain,
              Duration_Ms => Duration_Ms,
              Reason      => Ada.Strings.Unbounded.Null_Unbounded_String,
              Timestamp   => Timestamp);
   end Make_Event;

   --  An empty mixer renders silence.
   procedure Test_Empty_Mixer_Silence is
      M      : Mixer_State;
      Params : constant Mix_Parameters := Default_Params;
      Buf    : Sample_Buffer (1 .. 512);
      Any    : Boolean := False;
   begin
      Reset (M);
      Render_Chunk (M, Buf, Params);
      for I in Buf'Range loop
         if Buf (I) /= 0.0 then
            Any := True;
         end if;
      end loop;
      Expect (not Any, "empty mixer should render silence");
   end Test_Empty_Mixer_Silence;

   --  A single voice produces nonzero output within its envelope.
   procedure Test_Single_Voice_Nonzero is
      M      : Mixer_State;
      Params : constant Mix_Parameters := Default_Params;
      Buf    : Sample_Buffer (1 .. 512);
      Max    : Float := 0.0;
   begin
      Reset (M);
      Add_Event (M, Make_Event (Tick, Gain => 0.8), Params);
      Expect (Active_Voice_Count (M) = 1, "one voice should be active");
      Render_Chunk (M, Buf, Params);
      for I in Buf'Range loop
         if abs (Buf (I)) > Max then
            Max := abs (Buf (I));
         end if;
      end loop;
      Expect (Max > 0.0, "single voice should produce nonzero output");
      Expect (Max <= 1.0, "output should be within [-1,1]");
   end Test_Single_Voice_Nonzero;

   --  Two simultaneous voices contribute to the same chunk.
   procedure Test_Two_Voices_Overlap is
      M      : Mixer_State;
      Params : constant Mix_Parameters := Default_Params;
      Buf_A  : Sample_Buffer (1 .. 512);
      Buf_AB : Sample_Buffer (1 .. 512);
      A      : Mixer_State;
   begin
      Reset (M);
      Reset (A);
      --  Solo A
      Add_Event (A, Make_Event (Tick, Gain => 0.5, Timestamp => 1000), Params);
      Render_Chunk (A, Buf_A, Params);
      --  A + B
      Add_Event (M, Make_Event (Tick, Gain => 0.5, Timestamp => 1000), Params);
      Add_Event (M, Make_Event (Bip,  Gain => 0.5, Timestamp => 1000), Params);
      Expect (Active_Voice_Count (M) = 2, "two voices should be active");
      Render_Chunk (M, Buf_AB, Params);

      --  The mixed output must differ from solo A somewhere (B contributes).
      declare
        Differs : Boolean := False;
      begin
         for I in Buf_A'Range loop
            if abs (Buf_AB (I) - Buf_A (I)) > 1.0e-6 then
               Differs := True;
               exit;
            end if;
         end loop;
         Expect (Differs, "second voice should contribute to the same chunk");
      end;
   end Test_Two_Voices_Overlap;

   --  A second event starts before the first event ends (overlap in time).
   procedure Test_Second_Starts_Before_First_Ends is
      M      : Mixer_State;
      Params : constant Mix_Parameters := Default_Params;
      Buf    : Sample_Buffer (1 .. 512);
   begin
      Reset (M);
      Add_Event (M, Make_Event (Tick, Gain => 0.5, Duration_Ms => 100), Params);
      Render_Chunk (M, Buf, Params);
      --  After one chunk, the first voice is still active.
      Expect (Active_Voice_Count (M) = 1, "first voice should still be active after one chunk");
      Add_Event (M, Make_Event (Bip, Gain => 0.5, Duration_Ms => 100), Params);
      Expect (Active_Voice_Count (M) = 2, "second voice should overlap the first");
   end Test_Second_Starts_Before_First_Ends;

   --  Voices expire at the expected frame.
   procedure Test_Voice_Expiry is
      M      : Mixer_State;
      Params : constant Mix_Parameters := Default_Params;
      Buf    : Sample_Buffer (1 .. 512);
      Chunks : Natural := 0;
   begin
      Reset (M);
      Add_Event (M, Make_Event (Tick, Gain => 0.5, Duration_Ms => 14), Params);
      Expect (Active_Voice_Count (M) = 1, "voice active at start");
      while Active_Voice_Count (M) > 0 and then Chunks < 10 loop
         Render_Chunk (M, Buf, Params);
         Chunks := Chunks + 1;
      end loop;
      Expect (Chunks <= 3, "voice should expire within ~2 chunks (got "
              & Natural'Image (Chunks) & ")");
      Expect (Active_Voice_Count (M) = 0, "voice should have expired");
   end Test_Voice_Expiry;

   --  Output stays within range under maximum polyphony at full gain.
   procedure Test_Max_Polyphony_Bounded is
      M      : Mixer_State;
      Params : constant Mix_Parameters := Default_Params;
      Buf    : Sample_Buffer (1 .. 512);
   begin
      Reset (M);
      for I in 1 .. Max_Voices loop
         Add_Event (M, Make_Event (Bip, Gain => 1.0, Timestamp => Milliseconds (1000 + I)),
                    Params);
      end loop;
      Expect (Active_Voice_Count (M) = Max_Voices, "all 16 voices should be active");
      Render_Chunk (M, Buf, Params);
      for I in Buf'Range loop
         Expect (Buf (I) <= 1.0 and then Buf (I) >= -1.0,
                 "max polyphony output out of range at " & Positive'Image (I));
      end loop;
   end Test_Max_Polyphony_Bounded;

   --  Ambient drive saturates at Ambient_Max when gain is high enough.
   procedure Test_Ambient_Saturation is
      M      : Mixer_State;
      Params : constant Mix_Parameters := Default_Params;
      Buf    : Sample_Buffer (1 .. 512);
   begin
      Reset (M);
      --  drive = 0.32 + 1.5*0.55 = 1.145; target = 1.145*0.30 = 0.3435
      --  saturates to Ambient_Max = 0.30
      Add_Event (M, Make_Event (Drone, Gain => 1.5), Params);
      Expect (abs (M.Ambient.Level - Params.Ambient_Max) < 1.0e-6,
              "ambient should saturate at Ambient_Max (got "
              & Float'Image (M.Ambient.Level) & ")");
      --  Render a few chunks; level must stay bounded.
      for I in 1 .. 4 loop
         Render_Chunk (M, Buf, Params);
         Expect (M.Ambient.Level <= Params.Ambient_Max + 1.0e-6,
                 "ambient level must not exceed Ambient_Max");
         Expect (M.Ambient.Level >= 0.0,
                 "ambient level must not go negative");
      end loop;
   end Test_Ambient_Saturation;

   --  Voice stealing is deterministic: oldest (lowest sequence) is replaced.
   procedure Test_Voice_Stealing_Deterministic is
      M1     : Mixer_State;
      M2     : Mixer_State;
      Params : constant Mix_Parameters := Default_Params;
      Buf1   : Sample_Buffer (1 .. 512);
      Buf2   : Sample_Buffer (1 .. 512);
   begin
      Reset (M1);
      Reset (M2);
      for I in 1 .. Max_Voices loop
         Add_Event (M1, Make_Event (Bip, Gain => 0.5, Timestamp => Milliseconds (1000 + I)),
                    Params);
         Add_Event (M2, Make_Event (Bip, Gain => 0.5, Timestamp => Milliseconds (1000 + I)),
                    Params);
      end loop;
      --  Add one more: steals the oldest (sequence 1).
      Add_Event (M1, Make_Event (Tick, Gain => 0.5, Timestamp => 9999), Params);
      Add_Event (M2, Make_Event (Tick, Gain => 0.5, Timestamp => 9999), Params);
      Expect (Active_Voice_Count (M1) = Max_Voices, "still 16 voices after steal");
      Render_Chunk (M1, Buf1, Params);
      Render_Chunk (M2, Buf2, Params);
      for I in Buf1'Range loop
         Expect (Buf1 (I) = Buf2 (I), "voice stealing should be deterministic");
      end loop;
   end Test_Voice_Stealing_Deterministic;

   --  Identical event sequences produce identical samples.
   procedure Test_Determinism is
      M1     : Mixer_State;
      M2     : Mixer_State;
      Params : constant Mix_Parameters := Default_Params;
      Buf1   : Sample_Buffer (1 .. 512);
      Buf2   : Sample_Buffer (1 .. 512);
   begin
      Reset (M1);
      Reset (M2);
      Add_Event (M1, Make_Event (Chirp, Gain => 0.6, Timestamp => 2000), Params);
      Add_Event (M2, Make_Event (Chirp, Gain => 0.6, Timestamp => 2000), Params);
      Render_Chunk (M1, Buf1, Params);
      Render_Chunk (M2, Buf2, Params);
      for I in Buf1'Range loop
         Expect (Buf1 (I) = Buf2 (I), "identical inputs should give identical samples");
      end loop;
   end Test_Determinism;

   --  Reset clears all voices and ambient state.
   procedure Test_Reset_Clears is
      M      : Mixer_State;
      Params : constant Mix_Parameters := Default_Params;
      Buf    : Sample_Buffer (1 .. 512);
   begin
      Reset (M);
      Add_Event (M, Make_Event (Drone, Gain => 0.5), Params);
      Add_Event (M, Make_Event (Bip, Gain => 0.5), Params);
      Expect (Active_Voice_Count (M) = 2, "two voices before reset");
      Expect (M.Ambient.Level > 0.0, "ambient level set before reset");
      Reset (M);
      Expect (Active_Voice_Count (M) = 0, "no voices after reset");
      Expect (M.Ambient.Level = 0.0, "ambient level cleared after reset");
      Expect (M.Sequence = 0, "sequence counter cleared after reset");
      Render_Chunk (M, Buf, Params);
      for I in Buf'Range loop
         Expect (Buf (I) = 0.0, "reset mixer should render silence");
      end loop;
   end Test_Reset_Clears;

   --  Chunk boundaries do not introduce oscillator discontinuities.
   procedure Test_Chunk_Continuity is
      M      : Mixer_State;
      Params : constant Mix_Parameters := Default_Params;
      Buf1   : Sample_Buffer (1 .. 512);
      Buf2   : Sample_Buffer (1 .. 512);
   begin
      Reset (M);
      Add_Event (M, Make_Event (Bip, Gain => 0.5, Duration_Ms => 100), Params);
      Render_Chunk (M, Buf1, Params);
      Render_Chunk (M, Buf2, Params);
      declare
        Max_Amp : Float := 0.0;
        Jump    : Float;
      begin
         for I in Buf1'Range loop
            if abs (Buf1 (I)) > Max_Amp then
               Max_Amp := abs (Buf1 (I));
            end if;
            if abs (Buf2 (I)) > Max_Amp then
               Max_Amp := abs (Buf2 (I));
            end if;
         end loop;
         Jump := abs (Buf2 (1) - Buf1 (Buf1'Last));
         Expect (Jump < 0.3 * Max_Amp,
                 "chunk boundary should be continuous (jump="
                 & Float'Image (Jump) & " max=" & Float'Image (Max_Amp) & ")");
      end;
   end Test_Chunk_Continuity;

   --  To_Int16 clamps and rounds correctly.
   procedure Test_To_Int16 is
   begin
      Expect (Beep.Audio.Shared.To_Int16 (0.0) = 0, "To_Int16 zero");
      Expect (Beep.Audio.Shared.To_Int16 (1.0) = Interfaces.Integer_16 (32_767),
              "To_Int16 +1 clamps to max");
      Expect (Beep.Audio.Shared.To_Int16 (-1.0) = Interfaces.Integer_16 (-32_767),
              "To_Int16 -1 clamps to min");
      Expect (Beep.Audio.Shared.To_Int16 (2.0) = Interfaces.Integer_16 (32_767),
              "To_Int16 over +1 clamps");
      Expect (Beep.Audio.Shared.To_Int16 (-2.0) = Interfaces.Integer_16 (-32_767),
              "To_Int16 under -1 clamps");
      Expect (abs (Integer (Beep.Audio.Shared.To_Int16 (0.5)) - 16_384) <= 1,
              "To_Int16 0.5 rounds near 16384");
   end Test_To_Int16;

   --  Ambient decay is time-based: N frames decay by the same factor
   --  regardless of chunking.
   procedure Test_Ambient_Decay_Time_Based is
      M1     : Mixer_State;
      M2     : Mixer_State;
      Params : constant Mix_Parameters := Default_Params;
      Buf    : Sample_Buffer (1 .. 512);
   begin
      Reset (M1);
      Reset (M2);
      Add_Event (M1, Make_Event (Drone, Gain => 0.5), Params);
      Add_Event (M2, Make_Event (Drone, Gain => 0.5), Params);
      Render_Chunk (M1, Buf, Params);
      Render_Chunk (M1, Buf, Params);
      declare
        L1 : constant Float := M1.Ambient.Level;
      begin
         Render_Chunk (M2, Buf, Params);
         Render_Chunk (M2, Buf, Params);
         Expect (abs (L1 - M2.Ambient.Level) < 1.0e-6,
                 "ambient decay should be time-based and chunking-independent");
      end;
   end Test_Ambient_Decay_Time_Based;

   --  The ambient bed is a single capped level, not a per-event sum. Its
   --  target is monotonic in event gain and saturates at Ambient_Max.
   procedure Test_Ambient_Accumulation is
      M1 : Mixer_State;
      M2 : Mixer_State;
      M3 : Mixer_State;
      Params : constant Mix_Parameters := Default_Params;
   begin
      Reset (M1);
      Reset (M2);
      Reset (M3);
      Add_Event (M1, Make_Event (Drone, Gain => 0.5), Params);
      Add_Event (M2, Make_Event (Drone, Gain => 1.0), Params);
      Add_Event (M3, Make_Event (Drone, Gain => 1.5), Params);

      --  drive(M1) = 0.32 + 0.5*0.55  = 0.595; level = 0.595*0.30 = 0.1785
      --  drive(M2) = 0.32 + 1.0*0.55  = 0.870; level = 0.870*0.30 = 0.261
      --  drive(M3) = 0.32 + 1.5*0.55  = 1.145; level = 1.145*0.30 -> capped 0.30

      Expect (M1.Ambient.Level < M2.Ambient.Level,
              "higher gain should give higher ambient level");
      Expect (M2.Ambient.Level < M3.Ambient.Level,
              "higher gain should give higher ambient level");
      Expect (abs (M3.Ambient.Level - Params.Ambient_Max) < 1.0e-6,
              "ambient should saturate at Ambient_Max");
   end Test_Ambient_Accumulation;

   --  Is_Busy reflects audible state: false when idle, true after an event,
   --  and false again once the voice retires (Tick has no ambient bed).
   procedure Test_Is_Busy is
      M      : Mixer_State;
      Params : constant Mix_Parameters := Default_Params;
      Buf    : Sample_Buffer (1 .. 512);
      Chunks : Natural := 0;
   begin
      Reset (M);
      Expect (not Is_Busy (M), "fresh mixer should be idle");

      Add_Event (M, Make_Event (Tick, Gain => 0.8), Params);
      Expect (Is_Busy (M), "mixer should be busy right after an event");

      --  Render until the voice retires.  A 100 ms voice is ~4410 frames =
      --  ~9 chunks, so 20 is ample.
      while Is_Busy (M) and then Chunks < 20 loop
         Render_Chunk (M, Buf, Params);
         Chunks := Chunks + 1;
      end loop;
      Expect (not Is_Busy (M), "mixer should be idle after the voice retires");
      Expect (Chunks in 1 .. 20, "voice should have retired within 20 chunks");
   end Test_Is_Busy;

   --  Ambient bed must keep decaying on ticks with no new events: the
   --  player renders while Is_Busy, so the tail is not cut off.
   procedure Test_Ambient_Continues_Without_Events is
      M      : Mixer_State;
      Params : constant Mix_Parameters := Default_Params;
      Buf    : Sample_Buffer (1 .. 512);
      Max_1  : Float := 0.0;
      Max_2  : Float := 0.0;
      Chunks : Natural := 0;
   begin
      Reset (M);
      Add_Event (M, Make_Event (Drone, Gain => 0.8), Params);
      Expect (Is_Busy (M), "ambient bed should be active after a Drone");

      --  Render one chunk (the Drone voice also plays, but the ambient bed
      --  is what must survive the voice retiring).
      Render_Chunk (M, Buf, Params);
      for I in Buf'Range loop
         if abs (Buf (I)) > Max_1 then
            Max_1 := abs (Buf (I));
         end if;
      end loop;
      Expect (Max_1 > 0.0, "first chunk should be audible");

      --  Render until the voice retires; the ambient bed must still be
      --  above the silence threshold afterwards.
      while Active_Voice_Count (M) > 0 and then Chunks < 20 loop
         Render_Chunk (M, Buf, Params);
         Chunks := Chunks + 1;
      end loop;

      Expect (Is_Busy (M), "ambient bed should still be busy after the voice retires");

      --  The next chunk (no new events) must still be audible: the bed
      --  decays rather than being frozen or dropped.
      Render_Chunk (M, Buf, Params);
      for I in Buf'Range loop
         if abs (Buf (I)) > Max_2 then
            Max_2 := abs (Buf (I));
         end if;
      end loop;
      Expect (Max_2 > 0.0, "ambient tail should keep rendering after the voice retires");
   end Test_Ambient_Continues_Without_Events;

   --  Full lifecycle on the null backend: Initialize, Emit, Shutdown must
   --  complete without deadlock and leave the engine inactive.  This
   --  exercises the player task's start/drain/stop path.  The native
   --  backend path needs a device and is covered by CI on macOS/Linux.
   --  NOTE: the player task is terminal, so this test must run last.
   procedure Test_Null_Backend_Lifecycle is
      Cfg    : Beep.Config.App_Config := (others => <>);
      Engine : Beep.Audio.Audio_Engine;
      Evt    : Sound_Event;
   begin
      --  The default config selects the native backend; force null so this
      --  test needs no audio device and works on any platform (including CI).
      Cfg.Audio_Backend := Ada.Strings.Unbounded.To_Unbounded_String ("null");
      Beep.Audio.Initialize (Engine, Cfg);
      Expect (Beep.Audio.Is_Active (Engine), "engine should be active after Initialize");

      Evt := (Motif       => Tick,
              Gain        => 0.5,
              Duration_Ms => 50,
              Reason      => Ada.Strings.Unbounded.Null_Unbounded_String,
              Timestamp   => 100);
      Beep.Audio.Emit (Engine, Cfg, Evt);

      --  Give the player a couple of ticks to drain the event.
      delay 0.05;

      --  Shutdown must return (no deadlock in Wait_Stopped).
      Beep.Audio.Shutdown (Engine);
      Expect (not Beep.Audio.Is_Active (Engine), "engine should be inactive after Shutdown");

      --  Repeated Shutdown is safe (idempotent).
      Beep.Audio.Shutdown (Engine);
   end Test_Null_Backend_Lifecycle;

begin
   --  The platform body declares a global Audio_Player task that auto-starts.
   --  On the null backend it simply drains an empty queue and paces, so it is
   --  harmless to leave running during the mixer tests (which use their own
   --  local Mixer_State values and never touch the task or the global mixer).
   --  We must NOT call Shutdown here: the player task is terminal, and a
   --  Shutdown marks Ctrl.Stopped, which would make the lifecycle test's
   --  Initialize a no-op.  The lifecycle test (last) is the sole Initialize/
   --  Shutdown pair for the shared task.
   Test_Empty_Mixer_Silence;
   Test_Single_Voice_Nonzero;
   Test_Two_Voices_Overlap;
   Test_Second_Starts_Before_First_Ends;
   Test_Voice_Expiry;
   Test_Max_Polyphony_Bounded;
   Test_Ambient_Saturation;
   Test_Voice_Stealing_Deterministic;
   Test_Determinism;
   Test_Reset_Clears;
   Test_Chunk_Continuity;
   Test_To_Int16;
   Test_Ambient_Decay_Time_Based;
   Test_Ambient_Accumulation;
   Test_Is_Busy;
   Test_Ambient_Continues_Without_Events;
   --  Terminal: starts and stops the shared player task.  Must be last.
   Test_Null_Backend_Lifecycle;
   Put_Line ("beep_audio_tests: OK");
exception
   when E : others =>
      Put_Line ("beep_audio_tests: FAIL: " & Ada.Exceptions.Exception_Message (E));
      raise;
end Beep_Audio_Tests;
