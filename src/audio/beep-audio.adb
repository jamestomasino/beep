with Ada.Characters.Handling;
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
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
         D := 140;
      elsif D > 260 then
         D := 260;
      elsif D < 18 then
         D := 18;
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
      Gain   : Float)
   is
      Duration_Ms : constant Positive := Effective_Duration_Ms (Event);
      Frames      : constant Positive := Positive (Integer (Engine.Sample_Rate) * Duration_Ms / 1000);
      Frequency   : constant Float := Motif_Frequency (Event.Motif);
      type Sample_Buffer is array (Positive range <>) of Integer_16;
      Buffer      : Sample_Buffer (1 .. Frames);
      Two_Pi      : constant Float := 2.0 * Ada.Numerics.Pi;
      Rate_F      : constant Float := Float (Engine.Sample_Rate);
      Written     : long;
   begin
      for I in Buffer'Range loop
         declare
            T          : constant Float := Float (I - 1) / Rate_F;
            Phase      : constant Float := Two_Pi * Frequency * T;
            N          : constant Float := Float (I - 1) / Float (Buffer'Length);
            Envelope   : Float := 1.0;
            Sample_F32 : Float;
         begin
            if N < 0.08 then
               Envelope := N / 0.08;
            elsif N > 0.88 then
               Envelope := (1.0 - N) / 0.12;
            end if;
            if Envelope < 0.0 then
               Envelope := 0.0;
            end if;

            Sample_F32 :=
              Ada.Numerics.Elementary_Functions.Sin (Phase) * Clamp01 (Gain) * Envelope;
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

   procedure Initialize (Engine : in out Audio_Engine; Cfg : Beep.Config.App_Config) is
      Requested : constant Backend_Kind := Backend_From_Config (Cfg);
      Device    : aliased System.Address := System.Null_Address;
      Device_Name : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.Null_Ptr;
      Err       : int;
   begin
      Engine := (others => <>);
      Engine.Backend := Requested;

      if Requested = Null_Backend then
         return;
      end if;

      if Requested = Bell_Backend then
         Engine.Active := True;
         return;
      end if;

      Device_Name := Interfaces.C.Strings.New_String ("default");
      Err := snd_pcm_open (Device'Access, Device_Name, Snd_Pcm_Stream_Playback, 0);
      Interfaces.C.Strings.Free (Device_Name);
      if Err < 0 then
         Engine.Backend := Bell_Backend;
         Engine.Active := True;
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
           100_000);
      if Err < 0 then
         declare
            Ignore : constant int := snd_pcm_close (Engine.Alsa_Handle);
         begin
            pragma Unreferenced (Ignore);
         end;
         Engine.Alsa_Handle := System.Null_Address;
         Engine.Backend := Bell_Backend;
         Engine.Active := True;
         Ada.Text_IO.Put_Line ("[warn] ALSA config failed; falling back to terminal bell backend");
         return;
      end if;

      Engine.Active := True;
   end Initialize;

   procedure Emit
     (Engine : in out Audio_Engine;
      Cfg    : Beep.Config.App_Config;
      Event  : Sound_Event)
   is
      Gain : constant Float := Clamp01 (Event.Gain * Cfg.Master_Volume);
   begin
      if not Engine.Active then
         return;
      end if;

      case Engine.Backend is
         when Null_Backend =>
            null;
         when Bell_Backend =>
            Emit_Bell (Gain);
         when Alsa_Backend =>
            if Engine.Alsa_Handle = System.Null_Address then
               Emit_Bell (Gain);
            else
               Emit_Alsa (Engine, Event, Gain);
            end if;
      end case;
   end Emit;

   procedure Shutdown (Engine : in out Audio_Engine) is
      Ignore : int;
   begin
      if Engine.Alsa_Handle /= System.Null_Address then
         Ignore := snd_pcm_close (Engine.Alsa_Handle);
         pragma Unreferenced (Ignore);
      end if;
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
