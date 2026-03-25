with Ada.Characters.Handling;
with Ada.Environment_Variables;
with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Strings.Unbounded.Text_IO;
with Ada.Text_IO;

package body Beep.Config is
   use Ada.Strings.Unbounded;
   use Beep.Core.Types;

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

   function Defaults return App_Config is
   begin
      return (others => <>);
   end Defaults;

   function With_Profile (Cfg : App_Config; Profile_Name : String) return App_Config is
      Profile : constant String := Ada.Characters.Handling.To_Lower (Profile_Name);
      Out_Cfg : App_Config := Cfg;
   begin
      Out_Cfg.Profile := To_Unbounded_String (Profile);

      if Profile = "calm" then
         Out_Cfg.Engine.Keyboard_Threshold        := 0.45;
         Out_Cfg.Engine.Mouse_Threshold           := 0.40;
         Out_Cfg.Engine.Keyboard_Yip_Intensity    := 0.78;
         Out_Cfg.Engine.Keyboard_Yip_Chance       := 0.24;
         Out_Cfg.Engine.Keyboard_Chirp_Chance     := 0.14;
         Out_Cfg.Engine.Mouse_Flick_Intensity     := 0.72;
         Out_Cfg.Engine.Mouse_Flick_Chance        := 0.22;
         Out_Cfg.Engine.Mouse_Click_Zap_Chance    := 0.85;
         Out_Cfg.Engine.Cpu_Active_Cutoff         := 0.18;
         Out_Cfg.Engine.Cpu_Busy_Cutoff           := 0.72;
         Out_Cfg.Engine.Hum_Active_Max            := 0.72;
         Out_Cfg.Engine.Hum_Base_Chance           := 0.92;
         Out_Cfg.Engine.Hum_Gain_Scale            := 0.62;
         Out_Cfg.Engine.Cpu_Warble_Active_Chance  := 0.10;
         Out_Cfg.Engine.Cpu_Warble_Busy_Chance    := 0.30;
         Out_Cfg.Engine.Process_Threshold         := 0.25;
         Out_Cfg.Engine.Memory_Threshold          := 0.30;
         Out_Cfg.Engine.System_Threshold          := 0.34;
         Out_Cfg.Engine.Network_Threshold         := 0.28;
         Out_Cfg.Engine.Process_Stutter_Intensity := 0.66;
         Out_Cfg.Engine.Process_Stutter_Chance    := 0.22;
         Out_Cfg.Engine.Memory_Warble_Intensity   := 0.58;
         Out_Cfg.Engine.Memory_Warble_Chance      := 0.16;
         Out_Cfg.Engine.System_Stutter_Intensity  := 0.62;
         Out_Cfg.Engine.System_Stutter_Chance     := 0.24;
         Out_Cfg.Engine.Network_Chirp_Intensity   := 0.68;
         Out_Cfg.Engine.Network_Chirp_Chance      := 0.30;
         Out_Cfg.Engine.Network_Stutter_Intensity := 0.80;
         Out_Cfg.Engine.Network_Stutter_Chance    := 0.18;
         Out_Cfg.Engine.Min_Gap_Ms                := 120;
         Out_Cfg.Engine.Cooldown_Ms               := 260;

         Out_Cfg.Synth.Hum_Freq_Min           := 62.0;
         Out_Cfg.Synth.Hum_Freq_Max           := 108.0;
         Out_Cfg.Synth.Drone_Freq_Min         := 48.0;
         Out_Cfg.Synth.Drone_Freq_Max         := 84.0;
         Out_Cfg.Synth.Ambient_Noise_Chance   := 0.55;
         Out_Cfg.Synth.Ambient_Noise_Gain     := 0.07;
         Out_Cfg.Synth.Ambient_Blip_Chance    := 0.48;
         Out_Cfg.Synth.Ambient_Blip_Gain      := 0.08;
         Out_Cfg.Synth.Cluster_Steps_Min      := 3;
         Out_Cfg.Synth.Cluster_Steps_Max      := 9;
         Out_Cfg.Synth.Cluster_Spacing_Min_Ms := 8;
         Out_Cfg.Synth.Cluster_Spacing_Max_Ms := 20;

      elsif Profile = "noisy" then
         Out_Cfg.Engine.Keyboard_Threshold        := 0.15;
         Out_Cfg.Engine.Mouse_Threshold           := 0.12;
         Out_Cfg.Engine.Keyboard_Yip_Intensity    := 0.60;
         Out_Cfg.Engine.Keyboard_Yip_Chance       := 0.48;
         Out_Cfg.Engine.Keyboard_Chirp_Chance     := 0.28;
         Out_Cfg.Engine.Mouse_Flick_Intensity     := 0.48;
         Out_Cfg.Engine.Mouse_Flick_Chance        := 0.44;
         Out_Cfg.Engine.Mouse_Click_Zap_Chance    := 1.00;
         Out_Cfg.Engine.Cpu_Active_Cutoff         := 0.20;
         Out_Cfg.Engine.Cpu_Busy_Cutoff           := 0.58;
         Out_Cfg.Engine.Hum_Active_Max            := 0.52;
         Out_Cfg.Engine.Hum_Base_Chance           := 0.44;
         Out_Cfg.Engine.Hum_Gain_Scale            := 0.48;
         Out_Cfg.Engine.Cpu_Warble_Active_Chance  := 0.28;
         Out_Cfg.Engine.Cpu_Warble_Busy_Chance    := 0.56;
         Out_Cfg.Engine.Process_Threshold         := 0.09;
         Out_Cfg.Engine.Memory_Threshold          := 0.12;
         Out_Cfg.Engine.System_Threshold          := 0.14;
         Out_Cfg.Engine.Network_Threshold         := 0.10;
         Out_Cfg.Engine.Process_Stutter_Intensity := 0.42;
         Out_Cfg.Engine.Process_Stutter_Chance    := 0.46;
         Out_Cfg.Engine.Memory_Warble_Intensity   := 0.30;
         Out_Cfg.Engine.Memory_Warble_Chance      := 0.40;
         Out_Cfg.Engine.System_Stutter_Intensity  := 0.36;
         Out_Cfg.Engine.System_Stutter_Chance     := 0.50;
         Out_Cfg.Engine.Network_Chirp_Intensity   := 0.42;
         Out_Cfg.Engine.Network_Chirp_Chance      := 0.58;
         Out_Cfg.Engine.Network_Stutter_Intensity := 0.58;
         Out_Cfg.Engine.Network_Stutter_Chance    := 0.44;
         Out_Cfg.Engine.Min_Gap_Ms                := 40;
         Out_Cfg.Engine.Cooldown_Ms               := 110;

         Out_Cfg.Synth.Hum_Freq_Min           := 74.0;
         Out_Cfg.Synth.Hum_Freq_Max           := 132.0;
         Out_Cfg.Synth.Drone_Freq_Min         := 56.0;
         Out_Cfg.Synth.Drone_Freq_Max         := 102.0;
         Out_Cfg.Synth.Wobble_Freq_Min        := 96.0;
         Out_Cfg.Synth.Wobble_Freq_Max        := 166.0;
         Out_Cfg.Synth.Ambient_Noise_Chance   := 0.46;
         Out_Cfg.Synth.Ambient_Noise_Gain     := 0.11;
         Out_Cfg.Synth.Ambient_Blip_Chance    := 0.42;
         Out_Cfg.Synth.Ambient_Blip_Gain      := 0.12;
         Out_Cfg.Synth.Cluster_Steps_Min      := 4;
         Out_Cfg.Synth.Cluster_Steps_Max      := 14;
         Out_Cfg.Synth.Cluster_Spacing_Min_Ms := 4;
         Out_Cfg.Synth.Cluster_Spacing_Max_Ms := 14;
         Out_Cfg.Synth.Stutter_Steps_Min      := 3;
         Out_Cfg.Synth.Stutter_Steps_Max      := 6;
         Out_Cfg.Synth.Stutter_Spacing_Min_Ms := 9;
         Out_Cfg.Synth.Stutter_Spacing_Max_Ms := 20;

      else
         Out_Cfg.Engine.Keyboard_Threshold        := 0.25;
         Out_Cfg.Engine.Mouse_Threshold           := 0.20;
         Out_Cfg.Engine.Keyboard_Yip_Intensity    := 0.72;
         Out_Cfg.Engine.Keyboard_Yip_Chance       := 0.38;
         Out_Cfg.Engine.Keyboard_Chirp_Chance     := 0.20;
         Out_Cfg.Engine.Mouse_Flick_Intensity     := 0.65;
         Out_Cfg.Engine.Mouse_Flick_Chance        := 0.33;
         Out_Cfg.Engine.Mouse_Click_Zap_Chance    := 1.00;
         Out_Cfg.Engine.Cpu_Active_Cutoff         := 0.22;
         Out_Cfg.Engine.Cpu_Busy_Cutoff           := 0.62;
         Out_Cfg.Engine.Hum_Active_Max            := 0.68;
         Out_Cfg.Engine.Hum_Base_Chance           := 0.88;
         Out_Cfg.Engine.Hum_Gain_Scale            := 0.58;
         Out_Cfg.Engine.Cpu_Warble_Active_Chance  := 0.18;
         Out_Cfg.Engine.Cpu_Warble_Busy_Chance    := 0.44;
         Out_Cfg.Engine.Process_Threshold         := 0.15;
         Out_Cfg.Engine.Memory_Threshold          := 0.18;
         Out_Cfg.Engine.System_Threshold          := 0.20;
         Out_Cfg.Engine.Network_Threshold         := 0.16;
         Out_Cfg.Engine.Process_Stutter_Intensity := 0.55;
         Out_Cfg.Engine.Process_Stutter_Chance    := 0.35;
         Out_Cfg.Engine.Memory_Warble_Intensity   := 0.44;
         Out_Cfg.Engine.Memory_Warble_Chance      := 0.28;
         Out_Cfg.Engine.System_Stutter_Intensity  := 0.50;
         Out_Cfg.Engine.System_Stutter_Chance     := 0.42;
         Out_Cfg.Engine.Network_Chirp_Intensity   := 0.60;
         Out_Cfg.Engine.Network_Chirp_Chance      := 0.46;
         Out_Cfg.Engine.Network_Stutter_Intensity := 0.72;
         Out_Cfg.Engine.Network_Stutter_Chance    := 0.30;
         Out_Cfg.Engine.Min_Gap_Ms                := 70;
         Out_Cfg.Engine.Cooldown_Ms               := 180;

         Out_Cfg.Synth.Hum_Freq_Min           := 68.0;
         Out_Cfg.Synth.Hum_Freq_Max           := 118.0;
         Out_Cfg.Synth.Drone_Freq_Min         := 52.0;
         Out_Cfg.Synth.Drone_Freq_Max         := 92.0;
         Out_Cfg.Synth.Wobble_Freq_Min        := 84.0;
         Out_Cfg.Synth.Wobble_Freq_Max        := 140.0;
         Out_Cfg.Synth.Ambient_Noise_Chance   := 0.40;
         Out_Cfg.Synth.Ambient_Noise_Gain     := 0.08;
         Out_Cfg.Synth.Ambient_Blip_Chance    := 0.36;
         Out_Cfg.Synth.Ambient_Blip_Gain      := 0.10;
         Out_Cfg.Synth.Cluster_Steps_Min      := 3;
         Out_Cfg.Synth.Cluster_Steps_Max      := 12;
         Out_Cfg.Synth.Cluster_Spacing_Min_Ms := 6;
         Out_Cfg.Synth.Cluster_Spacing_Max_Ms := 16;
         Out_Cfg.Synth.Stutter_Steps_Min      := 2;
         Out_Cfg.Synth.Stutter_Steps_Max      := 5;
         Out_Cfg.Synth.Stutter_Spacing_Min_Ms := 12;
         Out_Cfg.Synth.Stutter_Spacing_Max_Ms := 26;
         Out_Cfg.Profile                       := To_Unbounded_String ("normal");
      end if;

      return Out_Cfg;
   end With_Profile;

   function Parse_Bool (Value : String; Ok : out Boolean) return Boolean is
      V : constant String := Ada.Characters.Handling.To_Lower
        (Ada.Strings.Fixed.Trim (Value, Ada.Strings.Both));
   begin
      if V = "1" or else V = "true" or else V = "yes" or else V = "on" then
         Ok := True;
         return True;
      elsif V = "0" or else V = "false" or else V = "no" or else V = "off" then
         Ok := True;
         return False;
      else
         Ok := False;
         return False;
      end if;
   end Parse_Bool;

   function Parse_I64 (Value : String; Ok : out Boolean) return Long_Long_Integer is
   begin
      Ok := True;
      return Long_Long_Integer'Value (Ada.Strings.Fixed.Trim (Value, Ada.Strings.Both));
   exception
      when others =>
         Ok := False;
         return 0;
   end Parse_I64;

   function Parse_F32 (Value : String; Ok : out Boolean) return Float is
   begin
      Ok := True;
      return Float'Value (Ada.Strings.Fixed.Trim (Value, Ada.Strings.Both));
   exception
      when others =>
         Ok := False;
         return 0.0;
   end Parse_F32;

   procedure Apply_Key_Value (Cfg : in out App_Config; Key : String; Value : String) is
      K       : constant String := Ada.Characters.Handling.To_Lower (Ada.Strings.Fixed.Trim (Key, Ada.Strings.Both));
      V       : constant String := Ada.Strings.Fixed.Trim (Value, Ada.Strings.Both);
      Ok_Bool : Boolean;
      Ok_Num  : Boolean;
      B       : Boolean;
      F       : Float;
      I       : Long_Long_Integer;
   begin
      if K = "profile" then
         Cfg := With_Profile (Cfg, V);

      elsif K = "debug_fake_input" then
         B := Parse_Bool (V, Ok_Bool);
         if Ok_Bool then
            Cfg.Debug_Fake_Input := B;
         end if;

      elsif K = "enable_cpu" then
         B := Parse_Bool (V, Ok_Bool);
         if Ok_Bool then
            Cfg.Enable_Cpu := B;
         end if;

      elsif K = "enable_system" then
         B := Parse_Bool (V, Ok_Bool);
         if Ok_Bool then
            Cfg.Enable_System := B;
         end if;

      elsif K = "enable_network" then
         B := Parse_Bool (V, Ok_Bool);
         if Ok_Bool then
            Cfg.Enable_Network := B;
         end if;

      elsif K = "enable_x11" then
         B := Parse_Bool (V, Ok_Bool);
         if Ok_Bool then
            Cfg.Enable_X11 := B;
         end if;

      elsif K = "log_events" then
         B := Parse_Bool (V, Ok_Bool);
         if Ok_Bool then
            Cfg.Log_Events := B;
         end if;

      elsif K = "debug_cpu" then
         B := Parse_Bool (V, Ok_Bool);
         if Ok_Bool then
            Cfg.Debug_Cpu := B;
         end if;

      elsif K = "audio_backend" then
         Cfg.Audio_Backend := To_Unbounded_String (V);

      elsif K = "master_volume" then
         F := Parse_F32 (V, Ok_Num);
         if Ok_Num then
            Cfg.Master_Volume := Clamp01 (F);
         end if;

      elsif K = "ambient_level" then
         F := Parse_F32 (V, Ok_Num);
         if Ok_Num then
            Cfg.Ambient_Level := Clamp01 (F);
         end if;

      elsif K = "burst_density" then
         F := Parse_F32 (V, Ok_Num);
         if Ok_Num then
            Cfg.Burst_Density := Clamp01 (F);
         end if;

      elsif K = "keyboard_threshold" then F := Parse_F32 (V, Ok_Num); if Ok_Num then Cfg.Engine.Keyboard_Threshold := F; end if;
      elsif K = "mouse_threshold" then F := Parse_F32 (V, Ok_Num); if Ok_Num then Cfg.Engine.Mouse_Threshold := F; end if;
      elsif K = "keyboard_yip_intensity" then F := Parse_F32 (V, Ok_Num); if Ok_Num then Cfg.Engine.Keyboard_Yip_Intensity := F; end if;
      elsif K = "keyboard_yip_chance" then F := Parse_F32 (V, Ok_Num); if Ok_Num then Cfg.Engine.Keyboard_Yip_Chance := F; end if;
      elsif K = "keyboard_chirp_chance" then F := Parse_F32 (V, Ok_Num); if Ok_Num then Cfg.Engine.Keyboard_Chirp_Chance := F; end if;
      elsif K = "mouse_flick_intensity" then F := Parse_F32 (V, Ok_Num); if Ok_Num then Cfg.Engine.Mouse_Flick_Intensity := F; end if;
      elsif K = "mouse_flick_chance" then F := Parse_F32 (V, Ok_Num); if Ok_Num then Cfg.Engine.Mouse_Flick_Chance := F; end if;
      elsif K = "mouse_click_zap_chance" then F := Parse_F32 (V, Ok_Num); if Ok_Num then Cfg.Engine.Mouse_Click_Zap_Chance := F; end if;
      elsif K = "cpu_active_cutoff" then F := Parse_F32 (V, Ok_Num); if Ok_Num then Cfg.Engine.Cpu_Active_Cutoff := F; end if;
      elsif K = "cpu_busy_cutoff" then F := Parse_F32 (V, Ok_Num); if Ok_Num then Cfg.Engine.Cpu_Busy_Cutoff := F; end if;
      elsif K = "hum_active_max" then F := Parse_F32 (V, Ok_Num); if Ok_Num then Cfg.Engine.Hum_Active_Max := F; end if;
      elsif K = "hum_base_chance" then F := Parse_F32 (V, Ok_Num); if Ok_Num then Cfg.Engine.Hum_Base_Chance := F; end if;
      elsif K = "hum_gain_scale" then F := Parse_F32 (V, Ok_Num); if Ok_Num then Cfg.Engine.Hum_Gain_Scale := F; end if;
      elsif K = "cpu_warble_active_chance" then F := Parse_F32 (V, Ok_Num); if Ok_Num then Cfg.Engine.Cpu_Warble_Active_Chance := F; end if;
      elsif K = "cpu_warble_busy_chance" then F := Parse_F32 (V, Ok_Num); if Ok_Num then Cfg.Engine.Cpu_Warble_Busy_Chance := F; end if;
      elsif K = "process_threshold" then F := Parse_F32 (V, Ok_Num); if Ok_Num then Cfg.Engine.Process_Threshold := F; end if;
      elsif K = "memory_threshold" then F := Parse_F32 (V, Ok_Num); if Ok_Num then Cfg.Engine.Memory_Threshold := F; end if;
      elsif K = "system_threshold" then F := Parse_F32 (V, Ok_Num); if Ok_Num then Cfg.Engine.System_Threshold := F; end if;
      elsif K = "network_threshold" then F := Parse_F32 (V, Ok_Num); if Ok_Num then Cfg.Engine.Network_Threshold := F; end if;
      elsif K = "process_stutter_intensity" then F := Parse_F32 (V, Ok_Num); if Ok_Num then Cfg.Engine.Process_Stutter_Intensity := F; end if;
      elsif K = "process_stutter_chance" then F := Parse_F32 (V, Ok_Num); if Ok_Num then Cfg.Engine.Process_Stutter_Chance := F; end if;
      elsif K = "memory_warble_intensity" then F := Parse_F32 (V, Ok_Num); if Ok_Num then Cfg.Engine.Memory_Warble_Intensity := F; end if;
      elsif K = "memory_warble_chance" then F := Parse_F32 (V, Ok_Num); if Ok_Num then Cfg.Engine.Memory_Warble_Chance := F; end if;
      elsif K = "system_stutter_intensity" then F := Parse_F32 (V, Ok_Num); if Ok_Num then Cfg.Engine.System_Stutter_Intensity := F; end if;
      elsif K = "system_stutter_chance" then F := Parse_F32 (V, Ok_Num); if Ok_Num then Cfg.Engine.System_Stutter_Chance := F; end if;
      elsif K = "network_chirp_intensity" then F := Parse_F32 (V, Ok_Num); if Ok_Num then Cfg.Engine.Network_Chirp_Intensity := F; end if;
      elsif K = "network_chirp_chance" then F := Parse_F32 (V, Ok_Num); if Ok_Num then Cfg.Engine.Network_Chirp_Chance := F; end if;
      elsif K = "network_stutter_intensity" then F := Parse_F32 (V, Ok_Num); if Ok_Num then Cfg.Engine.Network_Stutter_Intensity := F; end if;
      elsif K = "network_stutter_chance" then F := Parse_F32 (V, Ok_Num); if Ok_Num then Cfg.Engine.Network_Stutter_Chance := F; end if;

      elsif K = "hum_freq_min" then F := Parse_F32 (V, Ok_Num); if Ok_Num then Cfg.Synth.Hum_Freq_Min := F; end if;
      elsif K = "hum_freq_max" then F := Parse_F32 (V, Ok_Num); if Ok_Num then Cfg.Synth.Hum_Freq_Max := F; end if;
      elsif K = "drone_freq_min" then F := Parse_F32 (V, Ok_Num); if Ok_Num then Cfg.Synth.Drone_Freq_Min := F; end if;
      elsif K = "drone_freq_max" then F := Parse_F32 (V, Ok_Num); if Ok_Num then Cfg.Synth.Drone_Freq_Max := F; end if;
      elsif K = "wobble_freq_min" then F := Parse_F32 (V, Ok_Num); if Ok_Num then Cfg.Synth.Wobble_Freq_Min := F; end if;
      elsif K = "wobble_freq_max" then F := Parse_F32 (V, Ok_Num); if Ok_Num then Cfg.Synth.Wobble_Freq_Max := F; end if;
      elsif K = "ambient_noise_chance" then F := Parse_F32 (V, Ok_Num); if Ok_Num then Cfg.Synth.Ambient_Noise_Chance := F; end if;
      elsif K = "ambient_noise_gain" then F := Parse_F32 (V, Ok_Num); if Ok_Num then Cfg.Synth.Ambient_Noise_Gain := F; end if;
      elsif K = "ambient_blip_chance" then F := Parse_F32 (V, Ok_Num); if Ok_Num then Cfg.Synth.Ambient_Blip_Chance := F; end if;
      elsif K = "ambient_blip_gain" then F := Parse_F32 (V, Ok_Num); if Ok_Num then Cfg.Synth.Ambient_Blip_Gain := F; end if;

      elsif K = "cluster_steps_min" then I := Parse_I64 (V, Ok_Num); if Ok_Num then Cfg.Synth.Cluster_Steps_Min := Integer (I); end if;
      elsif K = "cluster_steps_max" then I := Parse_I64 (V, Ok_Num); if Ok_Num then Cfg.Synth.Cluster_Steps_Max := Integer (I); end if;
      elsif K = "cluster_spacing_min_ms" then I := Parse_I64 (V, Ok_Num); if Ok_Num then Cfg.Synth.Cluster_Spacing_Min_Ms := Integer (I); end if;
      elsif K = "cluster_spacing_max_ms" then I := Parse_I64 (V, Ok_Num); if Ok_Num then Cfg.Synth.Cluster_Spacing_Max_Ms := Integer (I); end if;
      elsif K = "stutter_steps_min" then I := Parse_I64 (V, Ok_Num); if Ok_Num then Cfg.Synth.Stutter_Steps_Min := Integer (I); end if;
      elsif K = "stutter_steps_max" then I := Parse_I64 (V, Ok_Num); if Ok_Num then Cfg.Synth.Stutter_Steps_Max := Integer (I); end if;
      elsif K = "stutter_spacing_min_ms" then I := Parse_I64 (V, Ok_Num); if Ok_Num then Cfg.Synth.Stutter_Spacing_Min_Ms := Integer (I); end if;
      elsif K = "stutter_spacing_max_ms" then I := Parse_I64 (V, Ok_Num); if Ok_Num then Cfg.Synth.Stutter_Spacing_Max_Ms := Integer (I); end if;

      elsif K = "min_gap_ms" then I := Parse_I64 (V, Ok_Num); if Ok_Num then Cfg.Engine.Min_Gap_Ms := I; end if;
      elsif K = "cooldown_ms" then I := Parse_I64 (V, Ok_Num); if Ok_Num then Cfg.Engine.Cooldown_Ms := I; end if;
      else
         null;
      end if;
   end Apply_Key_Value;

   function Default_Config_Path return String is
      Home : constant String := Ada.Environment_Variables.Value ("HOME", "");
   begin
      if Home = "" then
         return "config/beep.conf";
      else
         return Home & "/.config/beep/config.conf";
      end if;
   end Default_Config_Path;

   function Load_File (Path : String; Base : App_Config) return App_Config is
      File : Ada.Text_IO.File_Type;
      Cfg  : App_Config := Base;
      Line : Unbounded_String;
      Sep  : Natural;
   begin
      Ada.Text_IO.Open (File => File, Mode => Ada.Text_IO.In_File, Name => Path);
      while not Ada.Text_IO.End_Of_File (File) loop
         Ada.Strings.Unbounded.Text_IO.Get_Line (File, Line);
         declare
            Raw : constant String := Ada.Strings.Fixed.Trim (To_String (Line), Ada.Strings.Both);
         begin
            if Raw'Length = 0 or else Raw (Raw'First) = '#' then
               null;
            else
               Sep := Ada.Strings.Fixed.Index (Raw, "=");
               if Sep > 1 and then Sep < Raw'Length then
                  Apply_Key_Value
                    (Cfg,
                     Raw (Raw'First .. Raw'First + Sep - 2),
                     Raw (Raw'First + Sep .. Raw'Last));
               end if;
            end if;
         end;
      end loop;
      Ada.Text_IO.Close (File);
      return Cfg;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         raise;
   end Load_File;
end Beep.Config;
