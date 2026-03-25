with Ada.Strings.Unbounded;
with Interfaces;

package Beep.Core.Types is
   subtype Milliseconds is Long_Long_Integer;

   type Activity_Kind is (Keyboard, Mouse, Cpu, Process, Memory, System, Network);
   type Cpu_Bucket is (Idle, Active, Busy);

   type Motif_Type is (
      Bip,
      Chirp,
      Tick,
      Cluster,
      Run,
      Yip,
      Stutter,
      Bloop,
      Zap,
      Drone,
      Hum,
      Pad,
      Warble,
      Whirr,
      Wheee,
      Wobble,
      Tsk
   );

   type Activity_Sample is record
      Kind       : Activity_Kind;
      Intensity  : Float;
      Timestamp  : Milliseconds;
      Source     : Ada.Strings.Unbounded.Unbounded_String := Ada.Strings.Unbounded.Null_Unbounded_String;
      Cpu_Bucket : Beep.Core.Types.Cpu_Bucket := Idle;
   end record;

   type Sound_Event is record
      Motif       : Motif_Type;
      Gain        : Float;
      Duration_Ms : Integer;
      Reason      : Ada.Strings.Unbounded.Unbounded_String := Ada.Strings.Unbounded.Null_Unbounded_String;
      Timestamp   : Milliseconds;
   end record;

   type Optional_Sound_Event is record
      Has_Value : Boolean := False;
      Value     : Sound_Event;
   end record;

   type Engine_Config is record
      Keyboard_Threshold        : Float := 0.25;
      Mouse_Threshold           : Float := 0.20;
      Keyboard_Yip_Intensity    : Float := 0.72;
      Keyboard_Yip_Chance       : Float := 0.38;
      Keyboard_Chirp_Chance     : Float := 0.20;
      Mouse_Flick_Intensity     : Float := 0.65;
      Mouse_Flick_Chance        : Float := 0.33;
      Mouse_Click_Zap_Chance    : Float := 1.00;
      Cpu_Active_Cutoff         : Float := 0.35;
      Cpu_Busy_Cutoff           : Float := 0.75;
      Hum_Active_Max            : Float := 0.58;
      Hum_Base_Chance           : Float := 0.52;
      Hum_Gain_Scale            : Float := 0.52;
      Cpu_Warble_Active_Chance  : Float := 0.18;
      Cpu_Warble_Busy_Chance    : Float := 0.44;
      Process_Threshold         : Float := 0.15;
      Memory_Threshold          : Float := 0.18;
      System_Threshold          : Float := 0.20;
      Network_Threshold         : Float := 0.16;
      Process_Stutter_Intensity : Float := 0.55;
      Process_Stutter_Chance    : Float := 0.35;
      Memory_Warble_Intensity   : Float := 0.44;
      Memory_Warble_Chance      : Float := 0.28;
      System_Stutter_Intensity  : Float := 0.50;
      System_Stutter_Chance     : Float := 0.42;
      Network_Chirp_Intensity   : Float := 0.60;
      Network_Chirp_Chance      : Float := 0.46;
      Network_Stutter_Intensity : Float := 0.72;
      Network_Stutter_Chance    : Float := 0.30;
      Ambient_Level             : Float := 1.0;
      Burst_Density             : Float := 1.0;
      Min_Gap_Ms                : Milliseconds := 70;
      Cooldown_Ms               : Milliseconds := 180;
   end record;

   type Engine_State is record
      Last_Emit_Ms   : Milliseconds := 0;
      Last_Sample_Ms : Milliseconds := 0;
      Last_Motif     : Motif_Type := Bip;
      Has_Last_Motif : Boolean := False;
      Activity_Ema   : Float := 0.0;
      Rng_State      : Interfaces.Unsigned_32 := 16#9E3779B9#;
   end record;

   function New_State return Engine_State;
   function Default_Engine_Config return Engine_Config;
   function Motif_Image (Motif : Motif_Type) return String;
end Beep.Core.Types;
