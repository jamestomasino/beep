pragma SPARK_Mode (On);

package body Beep.Core.Safety is
   function Clamp_Unit (Value : Float) return Unit_Interval is
   begin
      if Value < 0.0 then
         return 0.0;
      elsif Value > 1.0 then
         return 1.0;
      else
         return Value;
      end if;
   end Clamp_Unit;

   function Saturating_Scale (Value : Float; Scale : Float) return Unit_Interval is
   begin
      if Scale = 0.0 then
         return 0.0;
      end if;

      if Scale < 1.0 then
         return Clamp_Unit (Value * Scale);
      end if;

      if Value <= 0.0 then
         return 0.0;
      elsif Value >= 1.0 / Scale then
         return 1.0;
      else
         return Clamp_Unit (Value * Scale);
      end if;
   end Saturating_Scale;
end Beep.Core.Safety;
