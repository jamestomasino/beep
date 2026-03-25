with Beep.Core.Types;

package Beep.Audio.Shared is
   function Clamp01 (Value : Float) return Float;

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
