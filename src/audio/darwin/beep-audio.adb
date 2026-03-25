with Ada.Characters.Handling;
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Beep.Audio.Runtime;
with Beep.Audio.Shared;
with Beep.Config;
with Interfaces.C;
with System;

package body Beep.Audio is
   use Ada.Strings.Unbounded;
   use Beep.Core.Types;
   use Interfaces.C;

   subtype Queued_Event is Beep.Audio.Runtime.Queued_Event;

   function beep_audio_stream_init (Sample_Rate : unsigned) return int
     with Import, Convention => C, External_Name => "beep_audio_stream_init";

   function beep_audio_stream_write (Samples : System.Address; Frames : unsigned) return int
     with Import, Convention => C, External_Name => "beep_audio_stream_write";

   procedure beep_audio_stream_shutdown
     with Import, Convention => C, External_Name => "beep_audio_stream_shutdown";

   function Clamp01 (Value : Float) return Float
     renames Beep.Audio.Shared.Clamp01;

   function Backend_From_Config (Cfg : Beep.Config.App_Config) return Backend_Kind is
      Raw : constant String := Ada.Characters.Handling.To_Lower (To_String (Cfg.Audio_Backend));
   begin
      if Raw = "null" then
         return Null_Backend;
      elsif Raw = "bell" then
         return Bell_Backend;
      elsif Raw = "coreaudio" or else Raw = "native" or else Raw = "afplay" or else Raw = "miniaudio" then
         return Alsa_Backend;
      else
         return Bell_Backend;
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

   procedure Emit_Stream
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
      type Sample_Buffer is array (Positive range <>) of aliased Interfaces.C.C_float;
      Buffer      : Sample_Buffer (1 .. Frames);
      Two_Pi      : constant Float := 2.0 * Ada.Numerics.Pi;
      Rate_F      : constant Float := Float (Engine.Sample_Rate);
      Rc          : int;
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
            Buffer (I) := Interfaces.C.C_float (Sample_F32);
         end;
      end loop;

      Rc := beep_audio_stream_write (Buffer'Address, unsigned (Buffer'Length));
      pragma Unreferenced (Rc);
   end Emit_Stream;

   procedure Emit_Ambient_Chunk
     (Engine : in out Audio_Engine;
      Ambient_Freq : Float;
      Ambient_Gain : Float)
   is
      Duration_Ms : constant Positive := 44;
      Frames      : constant Positive := Positive (Integer (Engine.Sample_Rate) * Duration_Ms / 1000);
      type Sample_Buffer is array (Positive range <>) of aliased Interfaces.C.C_float;
      Buffer      : Sample_Buffer (1 .. Frames);
      Two_Pi      : constant Float := 2.0 * Ada.Numerics.Pi;
      Rate_F      : constant Float := Float (Engine.Sample_Rate);
      Phase_Step  : constant Float := Two_Pi * Ambient_Freq / Rate_F;
      Rc          : int;
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
            Buffer (I) := Interfaces.C.C_float (S);
         end;
      end loop;

      Rc := beep_audio_stream_write (Buffer'Address, unsigned (Buffer'Length));
      pragma Unreferenced (Rc);
   end Emit_Ambient_Chunk;

   Queue : Beep.Audio.Runtime.Event_Queue;
   Ambient : Beep.Audio.Runtime.Ambient_Control;

   G_Backend     : Backend_Kind := Null_Backend;
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
                     Mix.Get (Ambient_Drive, Ambient_Max, Ambient_Decay, Mid_Min, Mid_Max, Fore_Attn);
                     Ambient.Snapshot (Ambient_Freq, Ambient_Gain, Ambient_Decay);
                     Shadow :=
                       (Backend => G_Backend,
                        Alsa_Handle => System.Null_Address,
                        Sample_Rate => G_Sample_Rate,
                        Active => G_Active);
                     Emit_Stream (Shadow, Item.Event, Item.Event.Gain, Ambient_Freq, Ambient_Gain, Mid_Min, Mid_Max, Fore_Attn);
               end case;
            end if;

         or
            delay 0.05;
            if G_Active and then G_Backend = Alsa_Backend then
               Mix.Get (Ambient_Drive, Ambient_Max, Ambient_Decay, Mid_Min, Mid_Max, Fore_Attn);
               Ambient.Snapshot (Ambient_Freq, Ambient_Gain, Ambient_Decay);
               if Ambient_Gain > 0.003 then
                  Shadow :=
                    (Backend => G_Backend,
                     Alsa_Handle => System.Null_Address,
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
      Requested : constant Backend_Kind := Backend_From_Config (Cfg);
      Raw       : constant String := Ada.Characters.Handling.To_Lower (To_String (Cfg.Audio_Backend));
      Rc        : int := 0;
   begin
      Engine := (others => <>);
      Engine.Backend := Requested;
      Queue.Start;
      Mix.Set (Cfg.Audio_Mix);
      G_Backend := Requested;
      G_Sample_Rate := Engine.Sample_Rate;
      G_Active := False;
      G_Ambient_Phase := 0.0;
      Ambient.Reset;

      if Requested = Null_Backend then
         Engine.Active := True;
         G_Active := True;
         return;
      end if;

      if Requested = Bell_Backend then
         Engine.Active := True;
         G_Active := True;
         return;
      end if;

      Rc := beep_audio_stream_init (Engine.Sample_Rate);
      if Rc = 0 then
         Engine.Backend := Bell_Backend;
         Engine.Active := True;
         G_Backend := Bell_Backend;
         G_Active := True;
         Ada.Text_IO.Put_Line ("[warn] Darwin audio stream unavailable; falling back to terminal bell backend");
         if Raw /= "bell" then
            Ada.Text_IO.Put_Line ("[warn] requested backend '" & Raw & "' could not be started") ;
         end if;
         return;
      end if;

      Engine.Active := True;
      G_Backend := Engine.Backend;
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
      Event  : Beep.Core.Types.Sound_Event)
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
   begin
      Queue.Stop;
      G_Active := False;
      beep_audio_stream_shutdown;

      G_Backend := Null_Backend;
      G_Ambient_Phase := 0.0;
      Ambient.Reset;

      Engine := (others => <>);
   end Shutdown;

   function Backend_Name (Engine : Audio_Engine) return String is
   begin
      case Engine.Backend is
         when Null_Backend => return "null";
         when Alsa_Backend => return "coreaudio";
         when Bell_Backend => return "bell";
      end case;
   end Backend_Name;

   function Is_Active (Engine : Audio_Engine) return Boolean is
   begin
      return Engine.Active;
   end Is_Active;
end Beep.Audio;
