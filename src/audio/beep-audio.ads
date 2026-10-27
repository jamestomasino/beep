with Beep.Config;
with Beep.Core.Types;
with Interfaces.C;
with System;

package Beep.Audio is
   --  Opaque audio backend state for the selected output engine.
   type Audio_Engine is private;

   --  Initialize backend resources according to Cfg.Audio_Backend.
   --  Reinitialization after Shutdown is not supported: the player task is
   --  terminal, so a post-shutdown Initialize is a no-op that leaves
   --  Engine.Active = False and logs a warning.
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
   --  Platform-neutral backend kinds.
   --    Null_Backend   : no output; events are drained and discarded.
   --    Native_Backend : the platform's native audio device. On Linux this
   --                     is ALSA; on macOS this is CoreAudio (AudioQueue).
   --                     The field name is backend-agnostic so the same
   --                     shared spec serves both platform bodies.
   --    Bell_Backend   : terminal bell (portable fallback).
   type Backend_Kind is (Null_Backend, Native_Backend, Bell_Backend);

   type Audio_Engine is record
      Backend     : Backend_Kind := Null_Backend;
      --  Opaque handle to the native audio device (ALSA pcm on Linux,
      --  CoreAudio queue on macOS). Null when the backend is not native.
      Native_Handle : System.Address := System.Null_Address;
      Sample_Rate : Interfaces.C.unsigned := 44_100;
      Active      : Boolean := False;
   end record;
end Beep.Audio;
