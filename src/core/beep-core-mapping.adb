with Ada.Containers.Vectors;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Interfaces;

package body Beep.Core.Mapping is
   use Ada.Strings.Unbounded;
   use Beep.Core.Types;
   use Interfaces;

   package Motif_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Motif_Type);

   function Clamp01 (Value : Float) return Float is
   begin
      if Value < 0.0 then
         return 0.0;
      elsif Value > 1.0 then
         return 1.0;
      else
         return Value;
      end if;
   end Clamp01;

   function Clamp_Gain (Value : Float) return Float is
   begin
      if Value < 0.03 then
         return 0.03;
      elsif Value > 1.0 then
         return 1.0;
      else
         return Value;
      end if;
   end Clamp_Gain;

   function Next_Rand (State : in out Engine_State) return Unsigned_32 is
   begin
      State.Rng_State := State.Rng_State * 1664525 + 1013904223;
      return State.Rng_State;
   end Next_Rand;

   function Rand01 (State : in out Engine_State) return Float is
   begin
      return Float (Next_Rand (State) and 16#FFFF#) / 65535.0;
   end Rand01;

   function Choose_Motif
     (State   : in out Engine_State;
      Options : Motif_Vectors.Vector) return Motif_Type
   is
      Index : Natural;
   begin
      if Options.Is_Empty then
         return Bip;
      end if;

      Index := Natural (Next_Rand (State) mod Unsigned_32 (Options.Length));
      return Options.Element (Positive (Index + 1));
   end Choose_Motif;

   function Is_Sequenced_Motif (Motif : Motif_Type) return Boolean is
   begin
      return Motif = Run or else Motif = Cluster or else Motif = Stutter;
   end Is_Sequenced_Motif;

   function Base_Duration_For_Motif (Motif : Motif_Type) return Integer is
   begin
      case Motif is
         when Drone =>
            return 7000;
         when Hum =>
            return 6200;
         when Pad =>
            return 9000;
         when Wobble =>
            return 180;
         when Whirr =>
            return 100;
         when Wheee =>
            return 130;
         when Warble =>
            return 130;
         when Cluster =>
            return 40;
         when Stutter =>
            return 70;
         when Run =>
            return 52;
         when Tick =>
            return 24;
         when Tsk =>
            return 30;
         when Zap =>
            return 24;
         when Yip =>
            return 32;
         when Chirp =>
            return 34;
         when Bloop =>
            return 58;
         when others =>
            return 42;
      end case;
   end Base_Duration_For_Motif;

   function Source_Contains (Source : Unbounded_String; Pattern : String) return Boolean is
   begin
      return Ada.Strings.Fixed.Index (To_String (Source), Pattern) > 0;
   end Source_Contains;

   function Map_Activity
     (State  : in out Engine_State;
      Cfg    : Engine_Config;
      Sample : Activity_Sample) return Optional_Sound_Event
   is
      Now_Ms          : constant Milliseconds := Sample.Timestamp;
      Dt              : Milliseconds := 60;
      Alpha           : Float;
      Density         : Float;
      Burst           : Float;
      Ambient         : Float;
      Motif           : Motif_Type := Bip;
      Reason          : Unbounded_String := Null_Unbounded_String;
      Gain            : Float := Sample.Intensity;
      Duration        : Integer := 55;
      Drop_Chance     : Float;
      Effective_Gap   : Milliseconds;
      Jitter          : Milliseconds;
      Motif_Cooldown  : Milliseconds;
      Dur_Scale       : Float;
      Min_Scale       : Float;
      Random_Chance   : Float;
      Density_Scale   : Float;
      Ambient_Scale   : Float;
      Options         : Motif_Vectors.Vector;
      Intensity_Clamp : Float := Clamp01 (Sample.Intensity);
   begin
      if State.Last_Sample_Ms > 0 then
         Dt := Now_Ms - State.Last_Sample_Ms;
      end if;

      if Dt < 10 then
         Dt := 10;
      elsif Dt > 1000 then
         Dt := 1000;
      end if;

      State.Last_Sample_Ms := Now_Ms;
      Alpha := Clamp01 (Float (Dt) / 220.0);
      State.Activity_Ema := State.Activity_Ema * (1.0 - Alpha) + Intensity_Clamp * Alpha;
      Density := Clamp01 (Float'Max (Sample.Intensity, State.Activity_Ema));
      Burst := Clamp01 (Cfg.Burst_Density);
      Ambient := Clamp01 (Cfg.Ambient_Level);
      Ambient_Scale := 0.55 + Ambient * 0.90;
      Density_Scale := (0.40 + Burst * 1.10) * Ambient_Scale;

      case Sample.Kind is
         when Keyboard =>
            if Sample.Intensity < Cfg.Keyboard_Threshold then
               return (Has_Value => False, others => <>);
            end if;

            Options.Append (Bip);
            Options.Append (Chirp);
            Options.Append (Tick);
            Options.Append (Cluster);
            Options.Append (Cluster);
            Options.Append (Cluster);
            Options.Append (Run);

            if Sample.Intensity > Cfg.Keyboard_Yip_Intensity
              and then Rand01 (State) < Clamp01 (Cfg.Keyboard_Yip_Chance)
            then
               Options.Append (Yip);
               Options.Append (Stutter);
               Options.Append (Stutter);
            end if;

            if Rand01 (State) < Clamp01 (Cfg.Keyboard_Chirp_Chance) then
               Options.Append (Chirp);
            end if;

            Motif := Choose_Motif (State, Options);
            Reason := To_Unbounded_String ("keyboard variety");

         when Mouse =>
            if Sample.Intensity < Cfg.Mouse_Threshold then
               return (Has_Value => False, others => <>);
            end if;

            Options.Append (Bip);
            Options.Append (Chirp);
            Options.Append (Tick);
            Options.Append (Cluster);
            Options.Append (Cluster);
            Options.Append (Cluster);
            Options.Append (Run);
            Options.Append (Bloop);

            if Sample.Intensity > Cfg.Mouse_Flick_Intensity
              and then Rand01 (State) < Clamp01 (Cfg.Mouse_Flick_Chance)
            then
               Options.Append (Yip);
               Options.Append (Stutter);
               Options.Append (Stutter);
            end if;

            if (Source_Contains (Sample.Source, "click") or else Source_Contains (Sample.Source, "press"))
              and then Rand01 (State) < Clamp01 (Cfg.Mouse_Click_Zap_Chance)
            then
               Options.Append (Zap);
               Options.Append (Zap);
            end if;

            Motif := Choose_Motif (State, Options);
            Reason := To_Unbounded_String ("mouse variety");

         when Cpu =>
            if Sample.Intensity < Cfg.Cpu_Active_Cutoff then
               Gain := Cfg.Cpu_Active_Cutoff;
            else
               Gain := Sample.Intensity;
            end if;

            case Sample.Cpu_Bucket is
               when Idle =>
                  if Rand01 (State) > Clamp01 (Cfg.Hum_Base_Chance * (0.45 + Ambient * 0.45)) then
                     return (Has_Value => False, others => <>);
                  end if;
                  Options.Append (Drone);
                  Options.Append (Hum);
                  Options.Append (Pad);
                  Options.Append (Warble);
                  Motif := Choose_Motif (State, Options);
                  Gain := 0.07 + Sample.Intensity * 0.24;
                  Reason := To_Unbounded_String ("cpu idle variety");

               when Active =>
                  Options.Append (Whirr);
                  Options.Append (Warble);
                  Options.Append (Cluster);
                  Options.Append (Run);
                  Options.Append (Tick);
                  Options.Append (Hum);
                  Options.Append (Drone);
                  Options.Append (Pad);
                  Options.Append (Wobble);
                  Options.Append (Cluster);
                  Options.Append (Cluster);
                  Options.Append (Cluster);
                  Options.Append (Run);
                  Motif := Choose_Motif (State, Options);

                  if Sample.Intensity < Cfg.Cpu_Active_Cutoff then
                     Gain := Cfg.Cpu_Active_Cutoff;
                  else
                     Gain := Sample.Intensity;
                  end if;
                  Reason := To_Unbounded_String ("cpu active variety");

               when Busy =>
                  Options.Append (Wheee);
                  Options.Append (Warble);
                  Options.Append (Stutter);
                  Options.Append (Cluster);
                  Options.Append (Run);
                  Options.Append (Zap);
                  Options.Append (Whirr);
                  Options.Append (Wobble);
                  Options.Append (Stutter);
                  Options.Append (Cluster);
                  Options.Append (Cluster);
                  Options.Append (Cluster);
                  Options.Append (Run);
                  Motif := Choose_Motif (State, Options);

                  if Sample.Intensity < Cfg.Cpu_Busy_Cutoff then
                     Gain := Cfg.Cpu_Busy_Cutoff;
                  else
                     Gain := Sample.Intensity;
                  end if;
                  Reason := To_Unbounded_String ("cpu busy variety");
            end case;

         when Process =>
            if Sample.Intensity < Cfg.Process_Threshold then
               return (Has_Value => False, others => <>);
            end if;
            Options.Append (Tick);
            Options.Append (Cluster);
            Options.Append (Stutter);
            Options.Append (Run);
            Options.Append (Chirp);
            Options.Append (Bip);
            Options.Append (Wobble);
            Options.Append (Cluster);
            Options.Append (Cluster);
            Options.Append (Cluster);
            Options.Append (Stutter);
            Options.Append (Run);
            Motif := Choose_Motif (State, Options);
            Reason := To_Unbounded_String ("process variety");

         when Memory =>
            if Sample.Intensity < Cfg.Memory_Threshold then
               return (Has_Value => False, others => <>);
            end if;
            Options.Append (Tsk);
            Options.Append (Warble);
            Options.Append (Cluster);
            Options.Append (Run);
            Options.Append (Chirp);
            Options.Append (Bloop);
            Options.Append (Wobble);
            Options.Append (Cluster);
            Options.Append (Cluster);
            Options.Append (Run);
            Motif := Choose_Motif (State, Options);
            Reason := To_Unbounded_String ("memory variety");

         when System =>
            if Sample.Intensity < Cfg.System_Threshold then
               return (Has_Value => False, others => <>);
            end if;
            Options.Append (Tick);
            Options.Append (Stutter);
            Options.Append (Cluster);
            Options.Append (Run);
            Options.Append (Bip);
            Options.Append (Tsk);
            Options.Append (Wobble);
            Options.Append (Stutter);
            Options.Append (Cluster);
            Options.Append (Cluster);
            Options.Append (Cluster);
            Options.Append (Run);
            Motif := Choose_Motif (State, Options);
            Gain := Sample.Intensity * 0.85;
            Reason := To_Unbounded_String ("system variety");

         when Network =>
            if Sample.Intensity < Cfg.Network_Threshold then
               return (Has_Value => False, others => <>);
            end if;
            Options.Append (Tsk);
            Options.Append (Chirp);
            Options.Append (Stutter);
            Options.Append (Cluster);
            Options.Append (Run);
            Options.Append (Zap);
            Options.Append (Bip);
            Options.Append (Wobble);
            Options.Append (Stutter);
            Options.Append (Cluster);
            Options.Append (Cluster);
            Options.Append (Cluster);
            Options.Append (Run);
            Motif := Choose_Motif (State, Options);
            Gain := Sample.Intensity * 0.95;
            Reason := To_Unbounded_String ("network variety");
      end case;

      Duration := Base_Duration_For_Motif (Motif);
      Drop_Chance := Clamp01 ((0.40 - Density * 0.25) / Density_Scale);

      if Motif = Hum or else Motif = Drone or else Motif = Wobble or else Motif = Pad then
         Drop_Chance := Clamp01 ((0.22 - Density * 0.10) / Density_Scale);
      elsif Motif = Tick or else Motif = Tsk then
         Drop_Chance := Clamp01 (Drop_Chance - 0.18);
      elsif Motif = Cluster then
         Drop_Chance := Clamp01 (Drop_Chance - 0.24);
      elsif Is_Sequenced_Motif (Motif) then
         Drop_Chance := Clamp01 (Drop_Chance - 0.14);
      end if;

      Random_Chance := Float (Next_Rand (State) and 16#FFFF#) / 65535.0;
      if Drop_Chance > 0.0 and then Random_Chance < Drop_Chance then
         return (Has_Value => False, others => <>);
      end if;

      Effective_Gap := Cfg.Min_Gap_Ms - Milliseconds (Float (Cfg.Min_Gap_Ms) * Density * 0.82);
      Effective_Gap := Milliseconds (Float (Effective_Gap) / Density_Scale);
      Jitter := Milliseconds (Integer (Next_Rand (State) mod 17) - 8);
      Effective_Gap := Effective_Gap + Jitter;
      if Effective_Gap < 12 then
         Effective_Gap := 12;
      end if;

      if Now_Ms - State.Last_Emit_Ms < Effective_Gap then
         return (Has_Value => False, others => <>);
      end if;

      Motif_Cooldown := Milliseconds (Float (Cfg.Cooldown_Ms) * (1.0 - Density));
      Motif_Cooldown := Milliseconds (Float (Motif_Cooldown) / Density_Scale);
      if Motif_Cooldown < 8 then
         Motif_Cooldown := 8;
      end if;

      if Motif = Hum or else Motif = Drone or else Motif = Wobble or else Motif = Pad then
         Motif_Cooldown := Motif_Cooldown * 2;
      elsif Motif = Cluster then
         Motif_Cooldown := Milliseconds (Float (Motif_Cooldown) * 0.45);
         if Motif_Cooldown < 3 then
            Motif_Cooldown := 3;
         end if;
      elsif Is_Sequenced_Motif (Motif) then
         Motif_Cooldown := Milliseconds (Float (Motif_Cooldown) * 0.60);
         if Motif_Cooldown < 4 then
            Motif_Cooldown := 4;
         end if;
      end if;

      if State.Has_Last_Motif
        and then Motif = State.Last_Motif
        and then Now_Ms - State.Last_Emit_Ms < Motif_Cooldown
        and then Density < 0.86
      then
         return (Has_Value => False, others => <>);
      end if;

      Dur_Scale := Clamp01 (1.0 - Density * 0.34);
      if Motif = Hum or else Motif = Drone or else Motif = Wobble or else Motif = Pad then
         Min_Scale := 0.82;
      else
         Min_Scale := 0.58;
      end if;

      if Dur_Scale < Min_Scale then
         Duration := Integer (Float (Duration) * Min_Scale);
      else
         Duration := Integer (Float (Duration) * Dur_Scale);
      end if;

      if Duration < 16 then
         Duration := 16;
      end if;

      Gain := Gain * (0.70 + Ambient * 0.45);

      State.Last_Emit_Ms := Now_Ms;
      State.Last_Motif := Motif;
      State.Has_Last_Motif := True;

      return (
         Has_Value => True,
         Value     => (
            Motif       => Motif,
            Gain        => Clamp_Gain (Gain),
            Duration_Ms => Duration,
            Reason      => Reason,
            Timestamp   => Now_Ms
         )
      );
   end Map_Activity;
end Beep.Core.Mapping;
