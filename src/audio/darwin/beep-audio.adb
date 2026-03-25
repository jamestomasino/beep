with Ada.Calendar;
with Ada.Characters.Handling;
with Ada.Directories;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Beep.Config;
with Interfaces.C;
with Interfaces.C.Strings;

package body Beep.Audio is
   use Ada.Strings.Unbounded;
   use Beep.Core.Types;

   Epoch : constant Ada.Calendar.Time := Ada.Calendar.Time_Of (1970, 1, 1, 0.0);

   Running_Darwin : constant Boolean := Ada.Directories.Exists ("/System/Library/Sounds");
   Last_Native_Play_Ms : Milliseconds := 0;

   function C_System (Command : Interfaces.C.Strings.chars_ptr) return Interfaces.C.int
     with Import, Convention => C, External_Name => "system";

   function Now_Ms return Milliseconds is
      Now_Time : constant Ada.Calendar.Time := Ada.Calendar.Clock;
      Elapsed  : constant Duration := Ada.Calendar."-" (Now_Time, Epoch);
   begin
      return Milliseconds (Long_Long_Integer (Elapsed * 1000.0));
   end Now_Ms;

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

   procedure Emit_Bell (Gain : Float) is
      use Ada.Text_IO;
   begin
      Put (Character'Val (7));
      if Gain > 0.72 then
         Put (Character'Val (7));
      end if;
      Flush;
   end Emit_Bell;

   procedure Emit_Darwin_Native (Gain : Float) is
      Cmd : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.Null_Ptr;
      Ts  : constant Milliseconds := Now_Ms;
      Rc  : Interfaces.C.int := 0;
   begin
      if Gain < 0.10 then
         return;
      end if;

      --  Rate limit system sound launches to avoid process spam.
      if Last_Native_Play_Ms > 0 and then Ts - Last_Native_Play_Ms < 90 then
         return;
      end if;
      Last_Native_Play_Ms := Ts;

      Cmd := Interfaces.C.Strings.New_String ("/bin/sh -c '/usr/bin/afplay /System/Library/Sounds/Pop.aiff >/dev/null 2>&1 &'" );
      Rc := C_System (Cmd);
      pragma Unreferenced (Rc);
      Interfaces.C.Strings.Free (Cmd);
   end Emit_Darwin_Native;

   procedure Initialize (Engine : in out Audio_Engine; Cfg : Beep.Config.App_Config) is
      Requested : constant Backend_Kind := Backend_From_Config (Cfg);
      Raw       : constant String := Ada.Characters.Handling.To_Lower (To_String (Cfg.Audio_Backend));
   begin
      Engine := (others => <>);
      Engine.Backend := Requested;

      case Requested is
         when Null_Backend =>
            Engine.Active := True;

         when Bell_Backend =>
            Engine.Active := True;
            if Raw /= "bell" then
               Ada.Text_IO.Put_Line
                 ("[warn] audio backend '" & Raw & "' is unavailable on this build; falling back to terminal bell backend");
            end if;

         when Alsa_Backend =>
            if Running_Darwin then
               Engine.Active := True;
            else
               Engine.Backend := Bell_Backend;
               Engine.Active := True;
               Ada.Text_IO.Put_Line
                 ("[warn] native macOS audio backend requested on non-macOS host; falling back to terminal bell backend");
            end if;
      end case;
   end Initialize;

   procedure Reconfigure (Engine : in out Audio_Engine; Cfg : Beep.Config.App_Config) is
   begin
      pragma Unreferenced (Engine, Cfg);
      null;
   end Reconfigure;

   procedure Emit
     (Engine : in out Audio_Engine;
      Cfg    : Beep.Config.App_Config;
      Event  : Beep.Core.Types.Sound_Event)
   is
      Gain : Float := Event.Gain;
   begin
      pragma Unreferenced (Cfg);

      if not Engine.Active then
         return;
      end if;

      if Gain < 0.0 then
         Gain := 0.0;
      elsif Gain > 1.0 then
         Gain := 1.0;
      end if;

      case Engine.Backend is
         when Null_Backend =>
            null;

         when Bell_Backend =>
            Emit_Bell (Gain);

         when Alsa_Backend =>
            if Running_Darwin then
               Emit_Darwin_Native (Gain);
            else
               Emit_Bell (Gain);
            end if;
      end case;
   end Emit;

   procedure Shutdown (Engine : in out Audio_Engine) is
   begin
      Engine := (others => <>);
   end Shutdown;

   function Backend_Name (Engine : Audio_Engine) return String is
   begin
      case Engine.Backend is
         when Null_Backend => return "null";
         when Alsa_Backend =>
            if Running_Darwin then
               return "coreaudio";
            end if;
            return "native";
         when Bell_Backend => return "bell";
      end case;
   end Backend_Name;

   function Is_Active (Engine : Audio_Engine) return Boolean is
   begin
      return Engine.Active;
   end Is_Active;
end Beep.Audio;
