with Beep.Core.Types;

package Beep.Core.Mapping is
   --  Convert one sampled activity input into an optional sound event.
   --  State is updated for EMA/cooldown/RNG progression on each call.
   function Map_Activity
     (State  : in out Beep.Core.Types.Engine_State;
      Cfg    : Beep.Core.Types.Engine_Config;
      Sample : Beep.Core.Types.Activity_Sample) return Beep.Core.Types.Optional_Sound_Event;
end Beep.Core.Mapping;
