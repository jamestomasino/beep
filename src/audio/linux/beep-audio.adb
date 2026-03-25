with Ada.Characters.Handling;
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Beep.Config;
with Interfaces;
with Interfaces.C;
with Interfaces.C.Strings;
with System;

package body Beep.Audio is
   use Ada.Strings.Unbounded;
   use Beep.Core.Types;
   use Interfaces;
   use Interfaces.C;
   use type System.Address;

   Snd_Pcm_Stream_Playback : constant int := 0;
   Snd_Pcm_Access_Rw_Interleaved : constant int := 3;
   Snd_Pcm_Format_S16_Le : constant int := 2;

   type Queued_Event is record
      Has_Value : Boolean := False;
      Event     : Sound_Event;
   end record;

   type Event_Buffer is array (Positive range 1 .. 512) of Sound_Event;

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
         else
            Item.Has_Value := True;
            Item.Event := Buffer (Head);
            Head := (if Head = Buffer'Last then Buffer'First else Head + 1);
            Count := Count - 1;
         end if;
      end Pop;

      procedure Stop is
      begin
         Stop_Requested := True;
      end Stop;

      procedure Start is
      begin
         Stop_Requested := False;
      end Start;
   end Event_Queue;

   function snd_pcm_open
     (Pcm    : access System.Address;
      Name   : Interfaces.C.Strings.chars_ptr;
      Stream : int;
      Mode   : int) return int
     with Import, Convention => C, External_Name => "snd_pcm_open";

   function snd_pcm_close (Pcm : System.Address) return int
     with Import, Convention => C, External_Name => "snd_pcm_close";

   function snd_pcm_set_params
     (Pcm            : System.Address;
      Format         : int;
      Access_Mode    : int;
      Channels       : unsigned;
      Rate           : unsigned;
      Soft_Resample  : int;
      Latency_Us     : unsigned) return int
     with Import, Convention => C, External_Name => "snd_pcm_set_params";

   function snd_pcm_prepare (Pcm : System.Address) return int
     with Import, Convention => C, External_Name => "snd_pcm_prepare";

   function snd_pcm_writei
     (Pcm    : System.Address;
      Buffer : System.Address;
      Size   : long) return long
     with Import, Convention => C, External_Name => "snd_pcm_writei";

   function snd_pcm_recover
     (Pcm    : System.Address;
      Err    : int;
      Silent : int) return int
     with Import, Convention => C, External_Name => "snd_pcm_recover";

   function Clamp01 (Value : Float) return Float is
   begin
      if Value < 0.0 then
         return 0.0;
      elsif Value > 1.0 then
         return 1.0;
      else
         return Value;
      end if;
   end Clamp01;

   function Backend_From_Config (Cfg : Beep.Config.App_Config) return Backend_Kind is
      Raw : constant String := Ada.Characters.Handling.To_Lower (To_String (Cfg.Audio_Backend));
   begin
      if Raw = "null" then
         return Null_Backend;
      elsif Raw = "bell" then
         return Bell_Backend;
      else
         return Alsa_Backend;
      end if;
   end Backend_From_Config;

   function Effective_Duration_Ms (Event : Sound_Event) return Positive is
      D : Integer := Event.Duration_Ms;
   begin
      if Event.Motif = Drone or else Event.Motif = Hum or else Event.Motif = Pad then
         D := 95;
      elsif D > 160 then
         D := 160;
      elsif D < 14 then
         D := 14;
      end if;
      return Positive (D);
   end Effective_Duration_Ms;

   function Motif_Frequency (Motif : Motif_Type) return Float is
   begin
      case Motif is
         when Bip => return 740.0;
         when Chirp => return 920.0;
         when Tick => return 1200.0;
         when Cluster => return 860.0;
         when Run => return 680.0;
         when Yip => return 1080.0;
         when Stutter => return 560.0;
         when Bloop => return 420.0;
         when Zap => return 1600.0;
         when Drone => return 90.0;
         when Hum => return 120.0;
         when Pad => return 220.0;
         when Warble => return 360.0;
         when Whirr => return 510.0;
         when Wheee => return 740.0;
         when Wobble => return 150.0;
         when Tsk => return 1400.0;
      end case;
   end Motif_Frequency;

   function Is_Ambient_Motif (Motif : Motif_Type) return Boolean is
   begin
      return Motif = Drone or else Motif = Hum or else Motif = Pad;
   end Is_Ambient_Motif;

   function Mid_Blend_For_Motif
     (Motif     : Motif_Type;
      Timestamp : Milliseconds;
      Mid_Min   : Float;
      Mid_Max   : Float) return Float
   is
      Jitter : constant Float := Float ((Timestamp mod 17) + 1) / 18.0;
      Base   : Float;
   begin
      case Motif is
         when Tick | Tsk | Zap =>
            Base := 0.16 + Jitter * 0.18;
         when Cluster | Run | Stutter =>
            Base := 0.28 + Jitter * 0.24;
         when Chirp | Bip | Bloop | Yip =>
            Base := 0.20 + Jitter * 0.24;
         when Wheee | Whirr | Warble | Wobble =>
            Base := 0.26 + Jitter * 0.26;
         when others =>
            Base := 0.24;
      end case;
      return Mid_Min + (Mid_Max - Mid_Min) * Clamp01 (Base);
   end Mid_Blend_For_Motif;

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

   G_Ambient_Phase : Float := 0.0;
   Mix : Mix_Params;

   protected type Ambient_Control is
      procedure Drive (Motif : Motif_Type; Gain : Float; Drive_Scale : Float; Max_Level : Float);
      procedure Snapshot (Freq : out Float; Gain : out Float; Decay : Float);
      procedure Reset;
   private
      Target_Freq  : Float := 92.0;
      Current_Freq : Float := 92.0;
      Level        : Float := 0.0;
   end Ambient_Control;

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

   procedure Emit_Bell (Gain : Float) is
      use Ada.Text_IO;
   begin
      Put (Character'Val (7));
      if Gain > 0.72 then
         Put (Character'Val (7));
      end if;
      Flush;
   end Emit_Bell;

   procedure Emit_Alsa
     (Engine : in out Audio_Engine;
      Event  : Sound_Event;
      Gain   : Float;
      Ambient_Freq : Float := 0.0;
      Ambient_Gain : Float := 0.0;
      Mid_Min      : Float := 0.16;
      Mid_Max      : Float := 0.52;
      Fore_Attn    : Float := 0.55)
   is
      Duration_Ms : constant Positive := Effective_Duration_Ms (Event);
      Frames      : constant Positive := Positive (Integer (Engine.Sample_Rate) * Duration_Ms / 1000);
      Frequency   : constant Float := Motif_Frequency (Event.Motif);
      type Sample_Buffer is array (Positive range <>) of Integer_16;
      Buffer      : Sample_Buffer (1 .. Frames);
      Two_Pi      : constant Float := 2.0 * Ada.Numerics.Pi;
      Rate_F      : constant Float := Float (Engine.Sample_Rate);
      Written     : long;
      Ambient_Phase_Step : constant Float := Two_Pi * Ambient_Freq / Rate_F;
      Mid_Blend   : constant Float := Mid_Blend_For_Motif (Event.Motif, Event.Timestamp, Mid_Min, Mid_Max);
      Fore_Blend  : constant Float := 1.0 - Mid_Blend * Fore_Attn;
   begin
      for I in Buffer'Range loop
         declare
            T          : constant Float := Float (I - 1) / Rate_F;
            Phase      : constant Float := Two_Pi * Frequency * T;
            Mid_Phase  : constant Float := Two_Pi * (Frequency * 0.62) * T;
            N          : constant Float := Float (I - 1) / Float (Buffer'Length);
            Envelope   : Float := 1.0;
            Fore_S     : Float;
            Mid_S      : Float;
            Sample_F32 : Float;
            Ambient_S  : Float := 0.0;
         begin
            if N < 0.08 then
               Envelope := N / 0.08;
            elsif N > 0.88 then
               Envelope := (1.0 - N) / 0.12;
            end if;
            if Envelope < 0.0 then
               Envelope := 0.0;
            end if;

            if Ambient_Gain > 0.0 then
               Ambient_S := Ada.Numerics.Elementary_Functions.Sin (G_Ambient_Phase) * Ambient_Gain;
               G_Ambient_Phase := G_Ambient_Phase + Ambient_Phase_Step;
               if G_Ambient_Phase > Two_Pi then
                  G_Ambient_Phase := G_Ambient_Phase - Two_Pi;
               end if;
            end if;

            Fore_S := Ada.Numerics.Elementary_Functions.Sin (Phase) * Clamp01 (Gain) * Envelope * Fore_Blend;
            Mid_S := Ada.Numerics.Elementary_Functions.Sin (Mid_Phase) * Clamp01 (Gain) * Envelope * Mid_Blend;
            Sample_F32 := Fore_S + Mid_S;
            Sample_F32 := Sample_F32 + Ambient_S;
            if Sample_F32 > 1.0 then
               Sample_F32 := 1.0;
            elsif Sample_F32 < -1.0 then
               Sample_F32 := -1.0;
            end if;
            Buffer (I) := Integer_16 (Integer (Sample_F32 * 32_767.0));
         end;
      end loop;

      Written := snd_pcm_writei (Engine.Alsa_Handle, Buffer'Address, long (Buffer'Length));
      if Written < 0 then
         if snd_pcm_recover (Engine.Alsa_Handle, int (Written), 1) >= 0 then
            Written := snd_pcm_writei (Engine.Alsa_Handle, Buffer'Address, long (Buffer'Length));
            pragma Unreferenced (Written);
         else
            declare
               Ignore : constant int := snd_pcm_prepare (Engine.Alsa_Handle);
            begin
               pragma Unreferenced (Ignore);
            end;
         end if;
      end if;
   end Emit_Alsa;

   procedure Emit_Ambient_Chunk
     (Engine : in out Audio_Engine;
      Ambient_Freq : Float;
      Ambient_Gain : Float)
   is
      Duration_Ms : constant Positive := 44;
      Frames      : constant Positive := Positive (Integer (Engine.Sample_Rate) * Duration_Ms / 1000);
      type Sample_Buffer is array (Positive range <>) of Integer_16;
      Buffer      : Sample_Buffer (1 .. Frames);
      Two_Pi      : constant Float := 2.0 * Ada.Numerics.Pi;
      Rate_F      : constant Float := Float (Engine.Sample_Rate);
      Phase_Step  : constant Float := Two_Pi * Ambient_Freq / Rate_F;
      Written     : long;
   begin
      for I in Buffer'Range loop
         declare
            S : Float := Ada.Numerics.Elementary_Functions.Sin (G_Ambient_Phase) * Ambient_Gain;
         begin
            G_Ambient_Phase := G_Ambient_Phase + Phase_Step;
            if G_Ambient_Phase > Two_Pi then
               G_Ambient_Phase := G_Ambient_Phase - Two_Pi;
            end if;

            if S > 1.0 then
               S := 1.0;
            elsif S < -1.0 then
               S := -1.0;
            end if;
            Buffer (I) := Integer_16 (Integer (S * 32_767.0));
         end;
      end loop;

      Written := snd_pcm_writei (Engine.Alsa_Handle, Buffer'Address, long (Buffer'Length));
      if Written < 0 then
         if snd_pcm_recover (Engine.Alsa_Handle, int (Written), 1) >= 0 then
            Written := snd_pcm_writei (Engine.Alsa_Handle, Buffer'Address, long (Buffer'Length));
            pragma Unreferenced (Written);
         else
            declare
               Ignore : constant int := snd_pcm_prepare (Engine.Alsa_Handle);
            begin
               pragma Unreferenced (Ignore);
            end;
         end if;
      end if;
   end Emit_Ambient_Chunk;

   Queue : Event_Queue;
   Ambient : Ambient_Control;

   G_Backend     : Backend_Kind := Null_Backend;
   G_Alsa_Handle : System.Address := System.Null_Address;
   G_Sample_Rate : unsigned := 44_100;
   G_Active      : Boolean := False;

   task type Audio_Player;

   task body Audio_Player is
      Item   : Queued_Event;
      Shadow : Audio_Engine;
      Ambient_Freq : Float := 0.0;
      Ambient_Gain : Float := 0.0;
      Ambient_Drive : Float := 0.32;
      Ambient_Max   : Float := 0.30;
      Ambient_Decay : Float := 0.992;
      Mid_Min       : Float := 0.16;
      Mid_Max       : Float := 0.52;
      Fore_Attn     : Float := 0.55;
   begin
      loop
         select
            Queue.Pop (Item);
            exit when not Item.Has_Value;

            if G_Active then
               case G_Backend is
                  when Null_Backend =>
                     null;
                  when Bell_Backend =>
                     Emit_Bell (Item.Event.Gain);
                  when Alsa_Backend =>
                     if G_Alsa_Handle = System.Null_Address then
                        Emit_Bell (Item.Event.Gain);
                     else
                        Mix.Get (Ambient_Drive, Ambient_Max, Ambient_Decay, Mid_Min, Mid_Max, Fore_Attn);
                        Ambient.Snapshot (Ambient_Freq, Ambient_Gain, Ambient_Decay);
                        Shadow :=
                          (Backend => G_Backend,
                           Alsa_Handle => G_Alsa_Handle,
                           Sample_Rate => G_Sample_Rate,
                           Active => G_Active);
                        Emit_Alsa (Shadow, Item.Event, Item.Event.Gain, Ambient_Freq, Ambient_Gain, Mid_Min, Mid_Max, Fore_Attn);
                     end if;
               end case;
            end if;
         or
            delay 0.05;
            if G_Active and then G_Backend = Alsa_Backend and then G_Alsa_Handle /= System.Null_Address then
               Mix.Get (Ambient_Drive, Ambient_Max, Ambient_Decay, Mid_Min, Mid_Max, Fore_Attn);
               Ambient.Snapshot (Ambient_Freq, Ambient_Gain, Ambient_Decay);
               if Ambient_Gain > 0.003 then
                  Shadow :=
                    (Backend => G_Backend,
                     Alsa_Handle => G_Alsa_Handle,
                     Sample_Rate => G_Sample_Rate,
                     Active => G_Active);
                  Emit_Ambient_Chunk (Shadow, Ambient_Freq, Ambient_Gain);
               end if;
            end if;
         end select;
      end loop;
   end Audio_Player;

   Player : Audio_Player;

   procedure Initialize (Engine : in out Audio_Engine; Cfg : Beep.Config.App_Config) is
      Requested   : constant Backend_Kind := Backend_From_Config (Cfg);
      Device      : aliased System.Address := System.Null_Address;
      Device_Name : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.Null_Ptr;
      Err         : int;
   begin
      Engine := (others => <>);
      Engine.Backend := Requested;
      Queue.Start;
      Mix.Set (Cfg.Audio_Mix);
      G_Backend := Requested;
      G_Alsa_Handle := System.Null_Address;
      G_Sample_Rate := Engine.Sample_Rate;
      G_Active := False;
      G_Ambient_Phase := 0.0;
      Ambient.Reset;

      if Requested = Null_Backend then
         return;
      end if;

      if Requested = Bell_Backend then
         Engine.Active := True;
         G_Active := True;
         return;
      end if;

      Device_Name := Interfaces.C.Strings.New_String ("default");
      Err := snd_pcm_open (Device'Access, Device_Name, Snd_Pcm_Stream_Playback, 0);
      Interfaces.C.Strings.Free (Device_Name);
      if Err < 0 then
         Engine.Backend := Bell_Backend;
         Engine.Active := True;
         G_Backend := Bell_Backend;
         G_Active := True;
         Ada.Text_IO.Put_Line ("[warn] ALSA unavailable; falling back to terminal bell backend");
         return;
      end if;

      Engine.Alsa_Handle := Device;
      Err :=
        snd_pcm_set_params
          (Engine.Alsa_Handle,
           Snd_Pcm_Format_S16_Le,
           Snd_Pcm_Access_Rw_Interleaved,
           1,
           Engine.Sample_Rate,
           1,
           50_000);
      if Err < 0 then
         declare
            Ignore : constant int := snd_pcm_close (Engine.Alsa_Handle);
         begin
            pragma Unreferenced (Ignore);
         end;
         Engine.Alsa_Handle := System.Null_Address;
         Engine.Backend := Bell_Backend;
         Engine.Active := True;
         G_Backend := Bell_Backend;
         G_Alsa_Handle := System.Null_Address;
         G_Active := True;
         Ada.Text_IO.Put_Line ("[warn] ALSA config failed; falling back to terminal bell backend");
         return;
      end if;

      Engine.Active := True;
      G_Backend := Engine.Backend;
      G_Alsa_Handle := Engine.Alsa_Handle;
      G_Active := True;
   end Initialize;

   procedure Reconfigure (Engine : in out Audio_Engine; Cfg : Beep.Config.App_Config) is
   begin
      if not Engine.Active then
         return;
      end if;
      Mix.Set (Cfg.Audio_Mix);
   end Reconfigure;

   procedure Emit
     (Engine : in out Audio_Engine;
      Cfg    : Beep.Config.App_Config;
      Event  : Sound_Event)
   is
      Q : Sound_Event := Event;
      Ambient_Drive : Float := 0.32;
      Ambient_Max   : Float := 0.30;
      Ambient_Decay : Float := 0.992;
      Mid_Min       : Float := 0.16;
      Mid_Max       : Float := 0.52;
      Fore_Attn     : Float := 0.55;
   begin
      if not Engine.Active then
         return;
      end if;

      Mix.Set (Cfg.Audio_Mix);
      Q.Gain := Clamp01 (Event.Gain * Cfg.Master_Volume);
      if Is_Ambient_Motif (Q.Motif) then
         Mix.Get (Ambient_Drive, Ambient_Max, Ambient_Decay, Mid_Min, Mid_Max, Fore_Attn);
         pragma Unreferenced (Ambient_Decay, Mid_Min, Mid_Max, Fore_Attn);
         Ambient.Drive (Q.Motif, Q.Gain, Ambient_Drive, Ambient_Max);
      end if;
      Queue.Push (Q);
   end Emit;

   procedure Shutdown (Engine : in out Audio_Engine) is
      Ignore : int;
   begin
      Queue.Stop;
      G_Active := False;

      if Engine.Alsa_Handle /= System.Null_Address then
         Ignore := snd_pcm_close (Engine.Alsa_Handle);
         pragma Unreferenced (Ignore);
      end if;

      G_Backend := Null_Backend;
      G_Alsa_Handle := System.Null_Address;
      G_Ambient_Phase := 0.0;
      Ambient.Reset;

      Engine := (others => <>);
   end Shutdown;

   function Backend_Name (Engine : Audio_Engine) return String is
   begin
      case Engine.Backend is
         when Null_Backend => return "null";
         when Alsa_Backend => return "alsa";
         when Bell_Backend => return "bell";
      end case;
   end Backend_Name;

   function Is_Active (Engine : Audio_Engine) return Boolean is
   begin
      return Engine.Active;
   end Is_Active;
end Beep.Audio;
