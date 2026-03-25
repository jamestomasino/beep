with Ada.Strings.Unbounded;
with Beep.Core.Types;

package Beep.Config is
   --  Audio layering/mix controls.
   --  Values are normalized unless marked otherwise.
   type Audio_Mix_Config is record
      --  Amount of activity routed into the ambient bed [0.0, 1.0].
      Ambient_Bed_Drive         : Float := 0.32;
      --  Maximum ambient bed contribution [0.0, 1.0].
      Ambient_Bed_Max           : Float := 0.30;
      --  Exponential per-frame ambient decay factor, near 1.0.
      Ambient_Bed_Decay         : Float := 0.992;
      --  Minimum and maximum blend of motifs into mid-ground [0.0, 1.0].
      Mid_Blend_Min             : Float := 0.16;
      Mid_Blend_Max             : Float := 0.52;
      --  Foreground attenuation applied when motif is moved to mid-ground [0.0, 1.0].
      Mid_Foreground_Attenuation : Float := 0.55;
   end record;

   --  Per-source weighting and debouncing controls.
   type Signal_Config is record
      --  Source gain weights (1.0 means neutral).
      Keyboard_Weight   : Float := 1.15;
      Mouse_Weight      : Float := 1.10;
      Cpu_Weight        : Float := 0.92;
      Process_Weight    : Float := 1.00;
      Memory_Weight     : Float := 0.96;
      System_Weight     : Float := 0.78;
      Network_Weight    : Float := 0.95;

      --  Per-kind debounce windows in milliseconds.
      Keyboard_Min_Gap_Ms : Integer := 18;
      Mouse_Min_Gap_Ms    : Integer := 14;
      Cpu_Min_Gap_Ms      : Integer := 60;
      Process_Min_Gap_Ms  : Integer := 28;
      Memory_Min_Gap_Ms   : Integer := 38;
      System_Min_Gap_Ms   : Integer := 48;
      Network_Min_Gap_Ms  : Integer := 26;

      --  Source-specific post-sampling multipliers.
      Mouse_Click_Boost : Float := 1.22;
      X11_Keyboard_Boost : Float := 1.12;
      Psi_Weight        : Float := 0.72;
      Loadavg_Weight    : Float := 0.55;
      Disk_Weight       : Float := 0.90;
   end record;

   --  Synthesis-domain controls for motif rendering.
   type Synth_Config is record
      --  Frequency bounds in Hz.
      Hum_Freq_Min           : Float := 68.0;
      Hum_Freq_Max           : Float := 118.0;
      Drone_Freq_Min         : Float := 52.0;
      Drone_Freq_Max         : Float := 92.0;
      Wobble_Freq_Min        : Float := 84.0;
      Wobble_Freq_Max        : Float := 140.0;
      --  Probabilities and gains are normalized [0.0, 1.0].
      Ambient_Noise_Chance   : Float := 0.40;
      Ambient_Noise_Gain     : Float := 0.08;
      Ambient_Blip_Chance    : Float := 0.36;
      Ambient_Blip_Gain      : Float := 0.10;
      --  Sequence step counts and inter-step spacing in milliseconds.
      Cluster_Steps_Min      : Integer := 3;
      Cluster_Steps_Max      : Integer := 12;
      Cluster_Spacing_Min_Ms : Integer := 6;
      Cluster_Spacing_Max_Ms : Integer := 16;
      Stutter_Steps_Min      : Integer := 2;
      Stutter_Steps_Max      : Integer := 5;
      Stutter_Spacing_Min_Ms : Integer := 12;
      Stutter_Spacing_Max_Ms : Integer := 26;
   end record;

   --  Top-level runtime configuration loaded from defaults/profile/file/CLI.
   type App_Config is record
      Engine           : Beep.Core.Types.Engine_Config := (others => <>);
      Enable_Cpu       : Boolean := True;
      Enable_System    : Boolean := True;
      Enable_Network   : Boolean := True;
      Enable_X11       : Boolean := False;
      Log_Events       : Boolean := False;
      Debug_Cpu        : Boolean := False;
      Debug_Fake_Input : Boolean := False;
      Audio_Backend    : Ada.Strings.Unbounded.Unbounded_String := Ada.Strings.Unbounded.To_Unbounded_String ("miniaudio");
      Profile          : Ada.Strings.Unbounded.Unbounded_String := Ada.Strings.Unbounded.To_Unbounded_String ("normal");
      Master_Volume    : Float := 1.0;
      Ambient_Level    : Float := 1.0;
      Burst_Density    : Float := 1.0;
      Audio_Mix       : Audio_Mix_Config := (others => <>);
      Log_Stats        : Boolean := False;
      Stats_Interval_Ms : Integer := 1000;
      Signal           : Signal_Config := (others => <>);
      Synth            : Synth_Config := (others => <>);
   end record;

   --  Return baseline defaults.
   function Defaults return App_Config;
   --  Apply named profile deltas ("calm", "normal", "noisy").
   function With_Profile (Cfg : App_Config; Profile_Name : String) return App_Config;
   --  Return user config path (typically under ~/.config/beep/).
   function Default_Config_Path return String;
   --  Load key/value overrides from Path onto Base.
   function Load_File (Path : String; Base : App_Config) return App_Config;
end Beep.Config;
