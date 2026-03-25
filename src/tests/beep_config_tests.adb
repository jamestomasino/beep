with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Beep.Config;

procedure Beep_Config_Tests is
   use Ada.Strings.Unbounded;

   procedure Expect (Cond : Boolean; Msg : String) is
   begin
      if not Cond then
         raise Program_Error with Msg;
      end if;
   end Expect;

   procedure Test_Profile_Presets is
      Base  : Beep.Config.App_Config := Beep.Config.Defaults;
      Calm  : Beep.Config.App_Config := Beep.Config.With_Profile (Base, "calm");
      Noisy : Beep.Config.App_Config := Beep.Config.With_Profile (Base, "noisy");
   begin
      Expect (Calm.Engine.Keyboard_Threshold > Noisy.Engine.Keyboard_Threshold,
              "calm keyboard threshold should be higher than noisy");
      Expect (Calm.Engine.Min_Gap_Ms > Noisy.Engine.Min_Gap_Ms,
              "calm min gap should be higher than noisy");
   end Test_Profile_Presets;

   procedure Test_Load_File is
      Temp_Path : constant String := "/tmp/beep-config-test.conf";
      F         : Ada.Text_IO.File_Type;
      Cfg       : Beep.Config.App_Config := Beep.Config.With_Profile (Beep.Config.Defaults, "normal");
   begin
      Ada.Text_IO.Create (F, Ada.Text_IO.Out_File, Temp_Path);
      Ada.Text_IO.Put_Line (F, "profile=noisy");
      Ada.Text_IO.Put_Line (F, "enable_cpu=false");
      Ada.Text_IO.Put_Line (F, "master_volume=0.25");
      Ada.Text_IO.Put_Line (F, "min_gap_ms=123");
      Ada.Text_IO.Put_Line (F, "log_stats=true");
      Ada.Text_IO.Put_Line (F, "stats_interval_ms=1500");
      Ada.Text_IO.Put_Line (F, "signal_keyboard_weight=1.35");
      Ada.Text_IO.Put_Line (F, "signal_mouse_min_gap_ms=9");
      Ada.Text_IO.Put_Line (F, "signal_loadavg_weight=0.66");
      Ada.Text_IO.Put_Line (F, "audio_mix_ambient_bed_max=0.34");
      Ada.Text_IO.Put_Line (F, "audio_mix_ambient_bed_decay=0.989");
      Ada.Text_IO.Put_Line (F, "audio_mix_mid_blend_min=0.20");
      Ada.Text_IO.Close (F);

      Cfg := Beep.Config.Load_File (Temp_Path, Cfg);
      Expect (To_String (Cfg.Profile) = "noisy", "profile override failed");
      Expect (Cfg.Enable_Cpu = False, "enable_cpu parse failed");
      Expect (abs (Cfg.Master_Volume - 0.25) < 0.0001, "master_volume parse failed");
      Expect (Cfg.Engine.Min_Gap_Ms = 123, "min_gap_ms parse failed");
      Expect (Cfg.Log_Stats = True, "log_stats parse failed");
      Expect (Cfg.Stats_Interval_Ms = 1500, "stats_interval_ms parse failed");
      Expect (abs (Cfg.Signal.Keyboard_Weight - 1.35) < 0.0001, "signal_keyboard_weight parse failed");
      Expect (Cfg.Signal.Mouse_Min_Gap_Ms = 9, "signal_mouse_min_gap_ms parse failed");
      Expect (abs (Cfg.Signal.Loadavg_Weight - 0.66) < 0.0001, "signal_loadavg_weight parse failed");
      Expect (abs (Cfg.Audio_Mix.Ambient_Bed_Max - 0.34) < 0.0001, "audio_mix_ambient_bed_max parse failed");
      Expect (abs (Cfg.Audio_Mix.Ambient_Bed_Decay - 0.989) < 0.0001, "audio_mix_ambient_bed_decay parse failed");
      Expect (abs (Cfg.Audio_Mix.Mid_Blend_Min - 0.20) < 0.0001, "audio_mix_mid_blend_min parse failed");

      if Ada.Directories.Exists (Temp_Path) then
         Ada.Directories.Delete_File (Temp_Path);
      end if;
   end Test_Load_File;

begin
   Test_Profile_Presets;
   Test_Load_File;
   Ada.Text_IO.Put_Line ("beep_config_tests: OK");
exception
   when E : others =>
      Ada.Text_IO.Put_Line ("beep_config_tests: FAIL: " & Ada.Exceptions.Exception_Message (E));
      raise;
end Beep_Config_Tests;
