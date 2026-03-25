with Beep.Config;
with Beep.Core.Types;

package Beep.Audio.Runtime is
   use Beep.Core.Types;

   type Event_Buffer is array (Positive range 1 .. 512) of Sound_Event;

   type Queued_Event is record
      Has_Value : Boolean := False;
      Event     : Sound_Event;
   end record;

   protected type Event_Queue is
      procedure Push (Event : Sound_Event);
      entry Pop (Item : out Queued_Event);
      procedure Stop;
      procedure Start;
   private
      Buffer         : Event_Buffer;
      Head           : Positive := 1;
      Tail           : Positive := 1;
      Count          : Natural := 0;
      Stop_Requested : Boolean := False;
   end Event_Queue;

   protected type Mix_Params is
      procedure Set (Cfg : Beep.Config.Audio_Mix_Config);
      procedure Get
        (Ambient_Drive : out Float;
         Ambient_Max   : out Float;
         Ambient_Decay : out Float;
         Mid_Min       : out Float;
         Mid_Max       : out Float;
         Fore_Attn     : out Float);
   private
      Drive_Param : Float := 0.32;
      Max_Param   : Float := 0.30;
      Decay_Param : Float := 0.992;
      Mid_Min_P   : Float := 0.16;
      Mid_Max_P   : Float := 0.52;
      Fore_Attn_P : Float := 0.55;
   end Mix_Params;

   protected type Ambient_Control is
      procedure Drive (Motif : Motif_Type; Gain : Float; Drive_Scale : Float; Max_Level : Float);
      procedure Snapshot (Freq : out Float; Gain : out Float; Decay : Float);
      procedure Reset;
   private
      Target_Freq  : Float := 92.0;
      Current_Freq : Float := 92.0;
      Level        : Float := 0.0;
   end Ambient_Control;
end Beep.Audio.Runtime;
