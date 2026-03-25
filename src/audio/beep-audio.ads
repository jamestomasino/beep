with Beep.Config;
with Beep.Core.Types;
with Interfaces.C;
with System;

package Beep.Audio is
   type Audio_Engine is private;

   procedure Initialize (Engine : in out Audio_Engine; Cfg : Beep.Config.App_Config);
   procedure Emit
     (Engine : in out Audio_Engine;
      Cfg    : Beep.Config.App_Config;
      Event  : Beep.Core.Types.Sound_Event);
   procedure Shutdown (Engine : in out Audio_Engine);

   function Backend_Name (Engine : Audio_Engine) return String;
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
