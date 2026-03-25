with Beep.Core.Types;

package body Beep.Audio.Shared is
   use Beep.Core.Types;

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

   function Effective_Duration_Ms (Event : Sound_Event) return Positive is
      D : Integer := Event.Duration_Ms;
   begin
      if Event.Motif = Drone or else Event.Motif = Hum or else Event.Motif = Pad then
         D := 95;
      elsif D > 160 then
         D := 160;
      elsif D < 14 then
         D := 14;
      end if;
      return Positive (D);
   end Effective_Duration_Ms;

   function Motif_Frequency (Motif : Motif_Type) return Float is
   begin
      case Motif is
         when Bip => return 740.0;
         when Chirp => return 920.0;
         when Tick => return 1200.0;
         when Cluster => return 860.0;
         when Run => return 680.0;
         when Yip => return 1080.0;
         when Stutter => return 560.0;
         when Bloop => return 420.0;
         when Zap => return 1600.0;
         when Drone => return 90.0;
         when Hum => return 120.0;
         when Pad => return 220.0;
         when Warble => return 360.0;
         when Whirr => return 510.0;
         when Wheee => return 740.0;
         when Wobble => return 150.0;
         when Tsk => return 1400.0;
      end case;
   end Motif_Frequency;

   function Is_Ambient_Motif (Motif : Motif_Type) return Boolean is
   begin
      return Motif = Drone or else Motif = Hum or else Motif = Pad;
   end Is_Ambient_Motif;

   function Mid_Blend_For_Motif
     (Motif     : Motif_Type;
      Timestamp : Milliseconds;
      Mid_Min   : Float;
      Mid_Max   : Float) return Float
   is
      Jitter : constant Float := Float ((Timestamp mod 17) + 1) / 18.0;
      Base   : Float;
   begin
      case Motif is
         when Tick | Tsk | Zap =>
            Base := 0.16 + Jitter * 0.18;
         when Cluster | Run | Stutter =>
            Base := 0.28 + Jitter * 0.24;
         when Chirp | Bip | Bloop | Yip =>
            Base := 0.20 + Jitter * 0.24;
         when Wheee | Whirr | Warble | Wobble =>
            Base := 0.26 + Jitter * 0.26;
         when others =>
            Base := 0.24;
      end case;
      return Mid_Min + (Mid_Max - Mid_Min) * Clamp01 (Base);
   end Mid_Blend_For_Motif;
end Beep.Audio.Shared;
