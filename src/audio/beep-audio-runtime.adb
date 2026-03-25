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

      entry Pop (Item : out Queued_Event) when Count > 0 or else Stop_Requested is
      begin
         if Count = 0 then
            Item.Has_Value := False;
            --  One-shot wakeup for waiting consumer.
            Stop_Requested := False;
         else
            Item.Has_Value := True;
            Item.Event := Buffer (Head);
            Head := (if Head = Buffer'Last then Buffer'First else Head + 1);
            Count := Count - 1;
         end if;
      end Pop;

      procedure Stop is
      begin
         --  Drop queued events and wake consumer.
         Head := Buffer'First;
         Tail := Buffer'First;
         Count := 0;
         Stop_Requested := True;
      end Stop;

      procedure Start is
      begin
         Stop_Requested := False;
      end Start;
   end Event_Queue;

   protected body Mix_Params is
      procedure Set (Cfg : Beep.Config.Audio_Mix_Config) is
      begin
         Drive_Param := Clamp01 (Cfg.Ambient_Bed_Drive);
         Max_Param := Clamp01 (Cfg.Ambient_Bed_Max);
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
         Ambient_Max := Max_Param;
         Ambient_Decay := Decay_Param;
         Mid_Min := Mid_Min_P;
         Mid_Max := Mid_Max_P;
         Fore_Attn := Fore_Attn_P;
      end Get;
   end Mix_Params;

   protected body Ambient_Control is
      procedure Drive (Motif : Motif_Type; Gain : Float; Drive_Scale : Float; Max_Level : Float) is
         Driven : Float := Clamp01 (Gain) * Drive_Scale;
      begin
         case Motif is
            when Drone =>
               Target_Freq := 82.0;
               Driven := Driven * 1.00;
            when Hum =>
               Target_Freq := 112.0;
               Driven := Driven * 0.90;
            when Pad =>
               Target_Freq := 174.0;
               Driven := Driven * 0.75;
            when others =>
               return;
         end case;

         if Driven > Level then
            Level := Driven;
         else
            Level := Level + (Driven - Level) * 0.30;
         end if;

         if Level > Max_Level then
            Level := Max_Level;
         end if;
      end Drive;

      procedure Snapshot (Freq : out Float; Gain : out Float; Decay : Float) is
      begin
         Current_Freq := Current_Freq + (Target_Freq - Current_Freq) * 0.10;
         Level := Level * Decay;
         if Level < 0.001 then
            Level := 0.0;
         end if;
         Freq := Current_Freq;
         Gain := Level;
      end Snapshot;

      procedure Reset is
      begin
         Target_Freq := 92.0;
         Current_Freq := 92.0;
         Level := 0.0;
      end Reset;
   end Ambient_Control;
end Beep.Audio.Runtime;
