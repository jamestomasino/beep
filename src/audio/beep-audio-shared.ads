with Beep.Core.Types;
with Interfaces;

package Beep.Audio.Shared is
   function Clamp01 (Value : Float) return Float;

   --  Convert a normalized float sample to signed 16-bit PCM.
   --  Clamps to [-1.0, 1.0] and rounds (no truncation toward zero).
   function To_Int16 (Sample : Float) return Interfaces.Integer_16;

   function Effective_Duration_Ms
     (Event : Beep.Core.Types.Sound_Event) return Positive;

   function Motif_Frequency
     (Motif : Beep.Core.Types.Motif_Type) return Float;

   function Is_Ambient_Motif
     (Motif : Beep.Core.Types.Motif_Type) return Boolean;

   function Mid_Blend_For_Motif
     (Motif     : Beep.Core.Types.Motif_Type;
      Timestamp : Beep.Core.Types.Milliseconds;
      Mid_Min   : Float;
      Mid_Max   : Float) return Float;
end Beep.Audio.Shared;
