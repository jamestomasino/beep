with Beep.Config;
with Beep.Core.Types;
with Interfaces.C;
with System;

package Beep.Audio is
   --  Opaque audio backend state for the selected output engine.
   type Audio_Engine is private;

   --  Initialize backend resources according to Cfg.Audio_Backend.
   procedure Initialize (Engine : in out Audio_Engine; Cfg : Beep.Config.App_Config);
   --  Re-apply runtime audio parameters without restarting the process.
   procedure Reconfigure (Engine : in out Audio_Engine; Cfg : Beep.Config.App_Config);
   --  Render one mapped sound event.
   procedure Emit
     (Engine : in out Audio_Engine;
      Cfg    : Beep.Config.App_Config;
      Event  : Beep.Core.Types.Sound_Event);
   --  Release backend resources; safe to call multiple times.
   procedure Shutdown (Engine : in out Audio_Engine);

   --  Human-readable backend name used in logs.
   function Backend_Name (Engine : Audio_Engine) return String;
   --  True when backend initialization succeeded and output is available.
   function Is_Active (Engine : Audio_Engine) return Boolean;

private
   type Backend_Kind is (Null_Backend, Alsa_Backend, Bell_Backend);

   type Audio_Engine is record
      Backend     : Backend_Kind := Null_Backend;
      Alsa_Handle : System.Address := System.Null_Address;
      Sample_Rate : Interfaces.C.unsigned := 44_100;
      Active      : Boolean := False;
   end record;
end Beep.Audio;
