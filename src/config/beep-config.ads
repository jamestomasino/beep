with Ada.Strings.Unbounded;
with Beep.Core.Types;

package Beep.Config is
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
      Synth            : Synth_Config := (others => <>);
   end record;

   function Defaults return App_Config;
   function With_Profile (Cfg : App_Config; Profile_Name : String) return App_Config;
   function Default_Config_Path return String;
   function Load_File (Path : String; Base : App_Config) return App_Config;
end Beep.Config;
