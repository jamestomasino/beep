pragma SPARK_Mode (On);

package Beep.Core.Safety is
   subtype Unit_Interval is Float range 0.0 .. 1.0;

   function Clamp_Unit (Value : Float) return Unit_Interval
     with
       Post => Clamp_Unit'Result >= 0.0 and then Clamp_Unit'Result <= 1.0;

   function Saturating_Scale (Value : Float; Scale : Float) return Unit_Interval
     with
       Pre  => Scale >= 0.0,
       Post => Saturating_Scale'Result >= 0.0 and then Saturating_Scale'Result <= 1.0;
end Beep.Core.Safety;
