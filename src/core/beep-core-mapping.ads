with Beep.Core.Types;

package Beep.Core.Mapping is
   function Map_Activity
     (State  : in out Beep.Core.Types.Engine_State;
      Cfg    : Beep.Core.Types.Engine_Config;
      Sample : Beep.Core.Types.Activity_Sample) return Beep.Core.Types.Optional_Sound_Event;
end Beep.Core.Mapping;
