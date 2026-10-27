with Beep.Audio.Shared;

package body Beep.Audio.Runtime is
   function Clamp01 (Value : Float) return Float
     renames Beep.Audio.Shared.Clamp01;

   protected body Event_Queue is
      procedure Push (Event : Sound_Event) is
      begin
         if Stop_Requested then
            return;
         end if;

         if Count = Buffer'Length then
            Head := (if Head = Buffer'Last then Buffer'First else Head + 1);
            Count := Count - 1;
         end if;

         Buffer (Tail) := Event;
         Tail := (if Tail = Buffer'Last then Buffer'First else Tail + 1);
         Count := Count + 1;
      end Push;

      procedure Try_Pop (Item : out Queued_Event; Available : out Boolean) is
      begin
         if Count = 0 then
            Item.Has_Value := False;
            Available := False;
         else
            Item.Has_Value := True;
            Item.Event := Buffer (Head);
            Head := (if Head = Buffer'Last then Buffer'First else Head + 1);
            Count := Count - 1;
            Available := True;
         end if;
      end Try_Pop;

      procedure Stop is
      begin
         --  Drop queued events; the player observes Stop_Requested itself.
         Head := Buffer'First;
         Tail := Buffer'First;
         Count := 0;
         Stop_Requested := True;
      end Stop;

      procedure Start is
      begin
         Stop_Requested := False;
      end Start;

      function Is_Stopped return Boolean is
      begin
         return Stop_Requested;
      end Is_Stopped;
   end Event_Queue;

   protected body Mix_Params is
      procedure Set (Cfg : Beep.Config.Audio_Mix_Config) is
      begin
         Drive_Param := Clamp01 (Cfg.Ambient_Bed_Drive);
         Max_Param   := Clamp01 (Cfg.Ambient_Bed_Max);
         if Max_Param < 0.02 then
            Max_Param := 0.02;
         end if;

         if Cfg.Ambient_Bed_Decay > 0.0 and then Cfg.Ambient_Bed_Decay < 1.0 then
            Decay_Param := Cfg.Ambient_Bed_Decay;
         end if;

         Mid_Min_P := Clamp01 (Cfg.Mid_Blend_Min);
         Mid_Max_P := Clamp01 (Cfg.Mid_Blend_Max);
         if Mid_Max_P < Mid_Min_P then
            declare
               Tmp : constant Float := Mid_Max_P;
            begin
               Mid_Max_P := Mid_Min_P;
               Mid_Min_P := Tmp;
            end;
         end if;

         Fore_Attn_P := Clamp01 (Cfg.Mid_Foreground_Attenuation);
      end Set;

      procedure Get
        (Ambient_Drive : out Float;
         Ambient_Max   : out Float;
         Ambient_Decay : out Float;
         Mid_Min       : out Float;
         Mid_Max       : out Float;
         Fore_Attn     : out Float)
      is
      begin
         Ambient_Drive := Drive_Param;
         Ambient_Max   := Max_Param;
         Ambient_Decay := Decay_Param;
         Mid_Min       := Mid_Min_P;
         Mid_Max       := Mid_Max_P;
         Fore_Attn     := Fore_Attn_P;
      end Get;
   end Mix_Params;

   protected body Player_Control is
      procedure Request_Stop is
      begin
         Stop_Flag := True;
      end Request_Stop;

      procedure Mark_Started is
      begin
         Started_F := True;
      end Mark_Started;

      procedure Mark_Stopped is
      begin
         Stopped_F := True;
      end Mark_Stopped;

      function Stop_Requested return Boolean is
      begin
         return Stop_Flag;
      end Stop_Requested;

      function Started return Boolean is
      begin
         return Started_F;
      end Started;

      function Stopped return Boolean is
      begin
         return Stopped_F;
      end Stopped;

      --  Immediately available when the player never started (e.g. the
      --  null/bell path with no device) or already acknowledged termination,
      --  so repeated Shutdown calls cannot deadlock.
      entry Wait_Stopped when Stopped_F or else not Started_F is
      begin
         null;
      end Wait_Stopped;
   end Player_Control;
end Beep.Audio.Runtime;
