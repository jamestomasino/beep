with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;
with Beep.Audio.Shared;
with Beep.Core.Types;

package body Beep.Audio.Mixer is
   use Beep.Core.Types;

   Two_Pi : constant Float := 2.0 * Ada.Numerics.Pi;

   --  Per-sample decay factor derived from the per-call decay parameter.
   --  The existing per-call rate (0.992 per ~50 ms snapshot) is normalized
   --  to a per-sample rate at 44.1 kHz: 0.992^(44100/50) per sample.
   --  We compute it as exp(ln(Decay) * (Sample_Rate / Snapshot_Us * 1e6)).
   --  For simplicity and determinism, use a fixed reference:
   --  Snapshot interval was 50 ms = 0.05 s; at 44100 Hz that is 2205 samples.
   --  Per-sample factor = Decay ** (1/2205).
   function Per_Sample_Decay (Decay_Per_Call : Float) return Float is
      use Ada.Numerics.Elementary_Functions;
   begin
      if Decay_Per_Call <= 0.0 then
         return 0.0;
      end if;
      --  2205 samples per 50 ms snapshot at 44.1 kHz
      return Float (Exp (Log (Decay_Per_Call) / 2205.0));
   end Per_Sample_Decay;

   --  Envelope: linear attack 0..8%, sustain, linear release 88%..100%.
   --  Frame is the absolute sample index within the voice (0-based).
   function Envelope (Frame : Natural; Total : Positive) return Float is
      N : constant Float := Float (Frame) / Float (Total);
   begin
      if Frame >= Total then
         return 0.0;
      end if;
      if N < 0.08 then
         return N / 0.08;
      elsif N > 0.88 then
         return (1.0 - N) / 0.12;
      else
         return 1.0;
      end if;
   end Envelope;

   procedure Reset (M : in out Mixer_State) is
   begin
      M.Voices := (others => (others => <>));
      M.Ambient := (others => <>);
      M.Sequence := 0;
   end Reset;

   procedure Add_Event
     (M      : in out Mixer_State;
      Event  : Sound_Event;
      Params : Mix_Parameters)
   is
      use type Positive;
      Duration_Ms : constant Positive := Shared.Effective_Duration_Ms (Event);
      --  44100 Hz reference for frame count
      Frames      : constant Positive := Positive (44_100 * Duration_Ms / 1000);
      Frequency   : constant Float := Shared.Motif_Frequency (Event.Motif);
      Mid_Freq    : constant Float := Frequency * 0.62;
      Mid_Blend   : constant Float :=
        Shared.Mid_Blend_For_Motif (Event.Motif, Event.Timestamp,
                                   Params.Mid_Min, Params.Mid_Max);
      Fore_Attn   : constant Float := 1.0 - Mid_Blend * Params.Fore_Attn;
      Gain        : constant Float := Shared.Clamp01 (Event.Gain);
      Slot        : Natural;
      Min_Seq     : Natural := Natural'Last;
   begin
      --  Find a free slot or the oldest active voice (lowest sequence).
      Slot := 0;
      for I in Voice_Array'Range loop
         if not M.Voices (I).Active then
            Slot := I;
            exit;
         end if;
         if M.Voices (I).Sequence < Min_Seq then
            Min_Seq := M.Voices (I).Sequence;
            Slot := I;
         end if;
      end loop;

      M.Sequence := M.Sequence + 1;

      M.Voices (Slot).Active := True;
      M.Voices (Slot).Sequence := M.Sequence;
      M.Voices (Slot).Frequency := Frequency;
      M.Voices (Slot).Mid_Frequency := Mid_Freq;
      M.Voices (Slot).Gain := Gain;
      M.Voices (Slot).Total_Frames := Frames;
      M.Voices (Slot).Frame := 0;
      M.Voices (Slot).Fore_Phase := 0.0;
      M.Voices (Slot).Mid_Phase := 0.0;
      M.Voices (Slot).Mid_Blend := Mid_Blend;
      M.Voices (Slot).Fore_Attn := Fore_Attn;

      --  Ambient drive for ambient motifs.
      --  drive = base drive + gain * foreground-attenuation weight, shaped
      --  per motif, level = drive * Ambient_Max, capped at Ambient_Max.
      if Shared.Is_Ambient_Motif (Event.Motif) then
         declare
            Driven : Float := Params.Ambient_Drive + Event.Gain * Params.Fore_Attn;
         begin
            case Event.Motif is
               when Drone =>
                  M.Ambient.Target_Freq := 82.0;
                  Driven := Driven * 1.00;
               when Hum =>
                  M.Ambient.Target_Freq := 112.0;
                  Driven := Driven * 0.90;
               when Pad =>
                  M.Ambient.Target_Freq := 174.0;
                  Driven := Driven * 0.75;
               when others =>
                  null;
            end case;

            if Driven > M.Ambient.Level then
               M.Ambient.Level := Driven;
            else
               M.Ambient.Level := M.Ambient.Level + (Driven - M.Ambient.Level) * 0.30;
            end if;

            --  level = drive * Ambient_Max, capped at Ambient_Max.
            M.Ambient.Level := M.Ambient.Level * Params.Ambient_Max;

            if M.Ambient.Level > Params.Ambient_Max then
               M.Ambient.Level := Params.Ambient_Max;
            end if;
         end;
      end if;
   end Add_Event;

   procedure Render_Chunk
     (M      : in out Mixer_State;
      Output : out Sample_Buffer;
      Params : Mix_Parameters)
   is
      use type Positive;
      use type Natural;
      Frames      : constant Positive := Output'Length;
      Rate_F      : constant Float := 44_100.0;
      Decay_Ps    : constant Float := Per_Sample_Decay (Params.Ambient_Decay);
      Amb_Step    : constant Float :=
        (if M.Ambient.Target_Freq /= 0.0
         then Two_Pi * M.Ambient.Target_Freq / Rate_F
         else 0.0);
      --  Smooth frequency transition per sample (0.10 per 50 ms snapshot
      --  => per-sample factor)
      Freq_Smooth : constant Float :=
        1.0 - Ada.Numerics.Elementary_Functions.Exp
          (Ada.Numerics.Elementary_Functions.Log (1.0 - 0.10) / 2205.0);
      --  Per-voice phase steps, computed once per chunk.
      Fore_Steps  : array (Voice_Array'Range) of Float;
      Mid_Steps   : array (Voice_Array'Range) of Float;
   begin
      --  Pre-compute phase steps for active voices.
      for V in Voice_Array'Range loop
         if M.Voices (V).Active then
            Fore_Steps (V) := Two_Pi * M.Voices (V).Frequency / Rate_F;
            Mid_Steps  (V) := Two_Pi * M.Voices (V).Mid_Frequency / Rate_F;
         else
            Fore_Steps (V) := 0.0;
            Mid_Steps  (V) := 0.0;
         end if;
      end loop;

      --  1. Clear output.
      Output := (others => 0.0);

      --  2. Advance ambient frequency (smoothing).
      M.Ambient.Current_Freq :=
        M.Ambient.Current_Freq + (M.Ambient.Target_Freq - M.Ambient.Current_Freq) * Freq_Smooth;

      --  3. Render each frame.
      for I in 1 .. Frames loop
         declare
            Sample : Float := 0.0;
         begin
            --  Ambient contribution (phase advanced per-sample, inline).
            if M.Ambient.Level > 0.001 then
               Sample := Sample +
                 Ada.Numerics.Elementary_Functions.Sin (M.Ambient.Phase) * M.Ambient.Level;
               M.Ambient.Phase := M.Ambient.Phase + Amb_Step;
               if M.Ambient.Phase > Two_Pi then
                  M.Ambient.Phase := M.Ambient.Phase - Two_Pi;
               end if;
               M.Ambient.Level := M.Ambient.Level * Decay_Ps;
               if M.Ambient.Level < 0.001 then
                  M.Ambient.Level := 0.0;
               end if;
            end if;

            --  Active voices (phase advanced per-sample, inline).
            --  The envelope is evaluated at the voice's absolute sample index
            --  (Frame + I - 1) so it ramps correctly across chunk boundaries;
            --  Frame is advanced once per chunk below.
            for V in Voice_Array'Range loop
               if M.Voices (V).Active then
                  declare
                     Abs_Frame : constant Natural := M.Voices (V).Frame + I - 1;
                     Env  : constant Float :=
                       Envelope (Abs_Frame, M.Voices (V).Total_Frames);
                     Fore : constant Float :=
                       Ada.Numerics.Elementary_Functions.Sin (M.Voices (V).Fore_Phase)
                       * M.Voices (V).Gain * Env * M.Voices (V).Fore_Attn;
                     Mid  : constant Float :=
                       Ada.Numerics.Elementary_Functions.Sin (M.Voices (V).Mid_Phase)
                       * M.Voices (V).Gain * Env * M.Voices (V).Mid_Blend;
                  begin
                     Sample := Sample + Fore + Mid;
                     --  Advance phases for the next sample.
                     M.Voices (V).Fore_Phase := M.Voices (V).Fore_Phase + Fore_Steps (V);
                     if M.Voices (V).Fore_Phase > Two_Pi then
                        M.Voices (V).Fore_Phase := M.Voices (V).Fore_Phase - Two_Pi;
                     end if;
                     M.Voices (V).Mid_Phase := M.Voices (V).Mid_Phase + Mid_Steps (V);
                     if M.Voices (V).Mid_Phase > Two_Pi then
                        M.Voices (V).Mid_Phase := M.Voices (V).Mid_Phase - Two_Pi;
                     end if;
                  end;
               end if;
            end loop;

            --  6. Clamp to [-1.0, 1.0].
            if Sample > 1.0 then
               Sample := 1.0;
            elsif Sample < -1.0 then
               Sample := -1.0;
            end if;

            Output (I) := Sample;
         end;
      end loop;

      --  4. Advance frame positions.
      --  5. Retire completed voices.
      for V in Voice_Array'Range loop
         if M.Voices (V).Active then
            M.Voices (V).Frame := M.Voices (V).Frame + Frames;
            if M.Voices (V).Frame >= M.Voices (V).Total_Frames then
               M.Voices (V).Active := False;
               M.Voices (V).Sequence := 0;
            end if;
         end if;
      end loop;
   end Render_Chunk;

   function Active_Voice_Count (M : Mixer_State) return Natural is
      Count : Natural := 0;
   begin
      for V in Voice_Array'Range loop
         if M.Voices (V).Active then
            Count := Count + 1;
         end if;
      end loop;
      return Count;
   end Active_Voice_Count;
end Beep.Audio.Mixer;
