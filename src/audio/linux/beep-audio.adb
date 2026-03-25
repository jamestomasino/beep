with Ada.Characters.Handling;
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Beep.Config;
with Beep.Audio.Runtime;
with Beep.Audio.Shared;
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

   subtype Queued_Event is Beep.Audio.Runtime.Queued_Event;

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

   function Clamp01 (Value : Float) return Float
     renames Beep.Audio.Shared.Clamp01;

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

   function Effective_Duration_Ms (Event : Sound_Event) return Positive
     renames Beep.Audio.Shared.Effective_Duration_Ms;

   function Motif_Frequency (Motif : Motif_Type) return Float
     renames Beep.Audio.Shared.Motif_Frequency;

   function Is_Ambient_Motif (Motif : Motif_Type) return Boolean
     renames Beep.Audio.Shared.Is_Ambient_Motif;

   function Mid_Blend_For_Motif
     (Motif     : Motif_Type;
      Timestamp : Milliseconds;
      Mid_Min   : Float;
      Mid_Max   : Float) return Float
     renames Beep.Audio.Shared.Mid_Blend_For_Motif;

   G_Ambient_Phase : Float := 0.0;
   Mix : Beep.Audio.Runtime.Mix_Params;

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

   Queue : Beep.Audio.Runtime.Event_Queue;
   Ambient : Beep.Audio.Runtime.Ambient_Control;

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
            if not Item.Has_Value then
               --  Queue wake-up (for shutdown/restart), continue waiting.
               null;
            elsif G_Active then
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
