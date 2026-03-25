with Ada.Strings.Unbounded;
with Beep.Core.Types;

package Beep.Config is
   type Audio_Mix_Config is record
      Ambient_Bed_Drive         : Float := 0.32;
      Ambient_Bed_Max           : Float := 0.30;
      Ambient_Bed_Decay         : Float := 0.992;
      Mid_Blend_Min             : Float := 0.16;
      Mid_Blend_Max             : Float := 0.52;
      Mid_Foreground_Attenuation : Float := 0.55;
   end record;

   type Signal_Config is record
      Keyboard_Weight   : Float := 1.15;
      Mouse_Weight      : Float := 1.10;
      Cpu_Weight        : Float := 0.92;
      Process_Weight    : Float := 1.00;
      Memory_Weight     : Float := 0.96;
      System_Weight     : Float := 0.78;
      Network_Weight    : Float := 0.95;

      Keyboard_Min_Gap_Ms : Integer := 18;
      Mouse_Min_Gap_Ms    : Integer := 14;
      Cpu_Min_Gap_Ms      : Integer := 60;
      Process_Min_Gap_Ms  : Integer := 28;
      Memory_Min_Gap_Ms   : Integer := 38;
      System_Min_Gap_Ms   : Integer := 48;
      Network_Min_Gap_Ms  : Integer := 26;

      Mouse_Click_Boost : Float := 1.22;
      X11_Keyboard_Boost : Float := 1.12;
      Psi_Weight        : Float := 0.72;
      Loadavg_Weight    : Float := 0.55;
      Disk_Weight       : Float := 0.90;
   end record;

   type Synth_Config is record
      Hum_Freq_Min           : Float := 68.0;
      Hum_Freq_Max           : Float := 118.0;
      Drone_Freq_Min         : Float := 52.0;
      Drone_Freq_Max         : Float := 92.0;
      Wobble_Freq_Min        : Float := 84.0;
      Wobble_Freq_Max        : Float := 140.0;
      Ambient_Noise_Chance   : Float := 0.40;
      Ambient_Noise_Gain     : Float := 0.08;
      Ambient_Blip_Chance    : Float := 0.36;
      Ambient_Blip_Gain      : Float := 0.10;
      Cluster_Steps_Min      : Integer := 3;
      Cluster_Steps_Max      : Integer := 12;
      Cluster_Spacing_Min_Ms : Integer := 6;
      Cluster_Spacing_Max_Ms : Integer := 16;
      Stutter_Steps_Min      : Integer := 2;
      Stutter_Steps_Max      : Integer := 5;
      Stutter_Spacing_Min_Ms : Integer := 12;
      Stutter_Spacing_Max_Ms : Integer := 26;
   end record;

   type App_Config is record
      Engine           : Beep.Core.Types.Engine_Config := (others => <>);
      Enable_Cpu       : Boolean := True;
      Enable_System    : Boolean := True;
      Enable_Network   : Boolean := True;
      Enable_X11       : Boolean := True;
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

   function Defaults return App_Config;
   function With_Profile (Cfg : App_Config; Profile_Name : String) return App_Config;
   function Default_Config_Path return String;
   function Load_File (Path : String; Base : App_Config) return App_Config;
end Beep.Config;
