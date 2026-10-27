with Beep.Config;
with Beep.Core.Types;

package Beep.Audio.Runtime is
   use Beep.Core.Types;

   type Event_Buffer is array (Positive range 1 .. 512) of Sound_Event;

   type Queued_Event is record
      Has_Value : Boolean := False;
      Event     : Sound_Event;
   end record;

   --  Bounded event queue with drop-oldest when full. The only consumer is
   --  the single Audio_Player task, which uses Try_Pop (never blocks), so
   --  shutdown never has to wake a consumer parked in an entry.
   protected type Event_Queue is
      procedure Push (Event : Sound_Event);
      procedure Try_Pop (Item : out Queued_Event; Available : out Boolean);
      procedure Stop;
      procedure Start;
      function Is_Stopped return Boolean;
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

   --  Player lifecycle control. Shutdown order:
   --    1. Event_Queue.Stop          (no more events accepted)
   --    2. Request_Stop              (player exits within one pacing step)
   --    3. platform unblock if needed (macOS: signal the C bridge)
   --    4. Wait_Stopped              (player acknowledges termination)
   --    5. close device resources
   --  Wait_Stopped must never deadlock: it is a no-op once the player has
   --  marked itself stopped, and safe to call repeatedly.
   protected type Player_Control is
      procedure Request_Stop;
      procedure Mark_Started;
      procedure Mark_Stopped;
      function Stop_Requested return Boolean;
      function Started return Boolean;
      function Stopped return Boolean;
      entry Wait_Stopped;
   private
      Stop_Flag  : Boolean := False;
      Started_F  : Boolean := False;
      Stopped_F  : Boolean := False;
   end Player_Control;
end Beep.Audio.Runtime;
