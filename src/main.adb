with Ada.Command_Line;
with Ada.Characters.Handling;
with Ada.Environment_Variables;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Beep.Audio;
with Beep.Config;
with Beep.Core.Mapping;
with Beep.Core.Types;
with Beep.Linux.Samplers;
with Beep.Runtime.Signals;

procedure Main is
   use Ada.Strings.Unbounded;
   use Beep.Core.Types;

   function Starts_With (Text : String; Prefix : String) return Boolean is
   begin
      return Text'Length >= Prefix'Length and then Text (Text'First .. Text'First + Prefix'Length - 1) = Prefix;
   end Starts_With;

   function Value_Flag (Arg : String; Prefix : String) return String is
   begin
      if Starts_With (Arg, Prefix) then
         return Arg (Arg'First + Prefix'Length .. Arg'Last);
      end if;
      return "";
   end Value_Flag;

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

   function Source_Contains (Sample : Activity_Sample; Pattern : String) return Boolean is
   begin
      return Ada.Strings.Fixed.Index (To_String (Sample.Source), Pattern) > 0;
   end Source_Contains;

   function Kind_Weight (Cfg : Beep.Config.App_Config; Sample : Activity_Sample) return Float is
   begin
      case Sample.Kind is
         when Keyboard =>
            return Cfg.Signal.Keyboard_Weight;
         when Mouse =>
            return Cfg.Signal.Mouse_Weight;
         when Cpu =>
            return Cfg.Signal.Cpu_Weight;
         when Process =>
            return Cfg.Signal.Process_Weight;
         when Memory =>
            return Cfg.Signal.Memory_Weight;
         when Beep.Core.Types.System =>
            return Cfg.Signal.System_Weight;
         when Network =>
            return Cfg.Signal.Network_Weight;
      end case;
   end Kind_Weight;

   function Kind_Min_Gap (Cfg : Beep.Config.App_Config; Kind : Activity_Kind) return Milliseconds is
   begin
      case Kind is
         when Keyboard => return Milliseconds (Cfg.Signal.Keyboard_Min_Gap_Ms);
         when Mouse => return Milliseconds (Cfg.Signal.Mouse_Min_Gap_Ms);
         when Cpu => return Milliseconds (Cfg.Signal.Cpu_Min_Gap_Ms);
         when Process => return Milliseconds (Cfg.Signal.Process_Min_Gap_Ms);
         when Memory => return Milliseconds (Cfg.Signal.Memory_Min_Gap_Ms);
         when Beep.Core.Types.System => return Milliseconds (Cfg.Signal.System_Min_Gap_Ms);
         when Network => return Milliseconds (Cfg.Signal.Network_Min_Gap_Ms);
      end case;
   end Kind_Min_Gap;

   type Kind_Timestamps is array (Activity_Kind) of Milliseconds;
   type Kind_Counts is array (Activity_Kind) of Natural;

   function Rate_Image (Count : Natural; Elapsed_Ms : Milliseconds) return String is
      Seconds : constant Float := Float (Elapsed_Ms) / 1000.0;
      Rate    : Float := 0.0;
   begin
      if Seconds > 0.0 then
         Rate := Float (Count) / Seconds;
      end if;
      return Ada.Strings.Fixed.Trim (Float'Image (Rate), Ada.Strings.Both);
   end Rate_Image;

   procedure Emit_Stats
     (Counts      : Kind_Counts;
      Window_Ms   : Milliseconds;
      Window_End  : Milliseconds)
   is
      use Ada.Text_IO;
      Total : Natural := 0;
   begin
      for K in Activity_Kind loop
         Total := Total + Counts (K);
      end loop;

      Put_Line
        ("[stats " & Long_Long_Integer'Image (Window_End) & " +" & Long_Long_Integer'Image (Window_Ms) & "ms]"
         & " keyboard=" & Rate_Image (Counts (Keyboard), Window_Ms)
         & " mouse=" & Rate_Image (Counts (Mouse), Window_Ms)
         & " cpu=" & Rate_Image (Counts (Cpu), Window_Ms)
         & " process=" & Rate_Image (Counts (Process), Window_Ms)
         & " memory=" & Rate_Image (Counts (Memory), Window_Ms)
         & " system=" & Rate_Image (Counts (Beep.Core.Types.System), Window_Ms)
         & " net=" & Rate_Image (Counts (Network), Window_Ms)
         & " total=" & Rate_Image (Total, Window_Ms));
   end Emit_Stats;

   procedure Print_Usage is
      use Ada.Text_IO;
   begin
      Put_Line ("beep - activity sonifier CLI (Ada migration)");
      Put_Line ("flags:");
      Put_Line ("  -h, --help");
      Put_Line ("  -V, --version");
      Put_Line ("  -q, --quiet");
      Put_Line ("  -v, --verbose");
      Put_Line ("  -s, --silent");
      Put_Line ("  --config=<path>");
      Put_Line ("  --profile=<calm|normal|noisy>");
      Put_Line ("  --no-cpu");
      Put_Line ("  --no-system");
      Put_Line ("  --no-net");
      Put_Line ("  --no-x11");
      Put_Line ("  --debug-events");
      Put_Line ("  --debug-cpu");
      Put_Line ("  --debug-fake-input");
      Put_Line ("  --stats");
      Put_Line ("  --audio-null");
      Put_Line ("  --audio-bell");
   end Print_Usage;

   procedure Handle_Sample
     (State  : in out Engine_State;
      Audio  : in out Beep.Audio.Audio_Engine;
      Cfg    : Beep.Config.App_Config;
      Last_By_Kind : in out Kind_Timestamps;
      Event_Counts : in out Kind_Counts;
      Sample : Activity_Sample)
   is
      Weighted : Activity_Sample := Sample;
      Gap      : Milliseconds;
      Event    : Optional_Sound_Event;
   begin
      Weighted.Intensity := Clamp01 (Weighted.Intensity * Kind_Weight (Cfg, Weighted));

      if Source_Contains (Weighted, "linux.x11.mouse.click") then
         Weighted.Intensity := Clamp01 (Weighted.Intensity * Cfg.Signal.Mouse_Click_Boost);
      elsif Source_Contains (Weighted, "linux.x11.keyboard") then
         Weighted.Intensity := Clamp01 (Weighted.Intensity * Cfg.Signal.X11_Keyboard_Boost);
      elsif Source_Contains (Weighted, "linux.proc.psi") then
         Weighted.Intensity := Clamp01 (Weighted.Intensity * Cfg.Signal.Psi_Weight);
      elsif Source_Contains (Weighted, "linux.proc.loadavg") then
         Weighted.Intensity := Clamp01 (Weighted.Intensity * Cfg.Signal.Loadavg_Weight);
      elsif Source_Contains (Weighted, "linux.proc.disk") then
         Weighted.Intensity := Clamp01 (Weighted.Intensity * Cfg.Signal.Disk_Weight);
      end if;

      Gap := Kind_Min_Gap (Cfg, Weighted.Kind);
      if Last_By_Kind (Weighted.Kind) > 0 and then Weighted.Timestamp - Last_By_Kind (Weighted.Kind) < Gap then
         return;
      end if;
      Last_By_Kind (Weighted.Kind) := Weighted.Timestamp;

      Event := Beep.Core.Mapping.Map_Activity (State, Cfg.Engine, Weighted);
      if Event.Has_Value then
         Event_Counts (Weighted.Kind) := Event_Counts (Weighted.Kind) + 1;
         Beep.Audio.Emit (Audio, Cfg, Event.Value);
         if Cfg.Log_Events then
            Ada.Text_IO.Put_Line
              ("[" & Long_Long_Integer'Image (Event.Value.Timestamp) & "] "
               & Beep.Core.Types.Motif_Image (Event.Value.Motif)
               & " gain=" & Float'Image (Event.Value.Gain)
               & " duration=" & Integer'Image (Event.Value.Duration_Ms)
               & "ms");
         end if;
      end if;
   end Handle_Sample;

   Cfg              : Beep.Config.App_Config := Beep.Config.With_Profile (Beep.Config.Defaults, "normal");
   Config_Path      : Unbounded_String := To_Unbounded_String (Beep.Config.Default_Config_Path);
   Cli_Profile      : Unbounded_String := Null_Unbounded_String;
   Cli_No_Cpu       : Boolean := False;
   Cli_No_System    : Boolean := False;
   Cli_No_Net       : Boolean := False;
   Cli_No_X11       : Boolean := False;
   Cli_Debug_Events : Boolean := False;
   Cli_Debug_Cpu    : Boolean := False;
   Cli_Debug_Fake   : Boolean := False;
   Cli_Stats        : Boolean := False;
   Cli_Audio_Null   : Boolean := False;
   Cli_Audio_Bell   : Boolean := False;
   Cli_Quiet        : Boolean := False;
   Cli_Silent       : Boolean := False;
   Cli_Verbose      : Boolean := False;

   function Info_Enabled return Boolean is
   begin
      return Cli_Verbose or else (not Cli_Quiet and then not Cli_Silent);
   end Info_Enabled;

   function Warn_Enabled return Boolean is
   begin
      return Cli_Verbose or else (not Cli_Quiet and then not Cli_Silent);
   end Warn_Enabled;

   procedure Log_Info (Msg : String) is
   begin
      if Info_Enabled then
         Ada.Text_IO.Put_Line (Msg);
      end if;
   end Log_Info;

   procedure Log_Warn (Msg : String) is
   begin
      if Warn_Enabled then
         Ada.Text_IO.Put_Line ("[warn] " & Msg);
      end if;
   end Log_Warn;

   Did_Cleanup : Boolean := False;
   Stop_Requested : Boolean := False;
   Mapper_State : Engine_State := New_State;
   Last_By_Kind : Kind_Timestamps := (others => 0);
   Event_Counts : Kind_Counts := (others => 0);
   Stats_Window_Start : Milliseconds := 0;
   Wayland_Session : Boolean := False;
   X11_Seen_Input : Boolean := False;
   X11_No_Input_Warned : Boolean := False;
   Startup_Ts : Milliseconds := 0;
   Cpu_Sampler  : Beep.Linux.Samplers.Cpu_Sampler;
   Sys_Sampler  : Beep.Linux.Samplers.System_Sampler;
   Net_Sampler  : Beep.Linux.Samplers.Net_Sampler;
   X11_Sampler  : Beep.Linux.Samplers.X11_Sampler;
   Audio_Engine : Beep.Audio.Audio_Engine;

   procedure Cleanup is
   begin
      if Did_Cleanup then
         return;
      end if;
      Beep.Audio.Shutdown (Audio_Engine);
      Beep.Linux.Samplers.Shutdown (X11_Sampler);
      Did_Cleanup := True;
   end Cleanup;

   procedure Apply_Cli_Overrides (Config : in out Beep.Config.App_Config) is
   begin
      if Cli_No_Cpu then Config.Enable_Cpu := False; end if;
      if Cli_No_System then Config.Enable_System := False; end if;
      if Cli_No_Net then Config.Enable_Network := False; end if;
      if Cli_No_X11 then Config.Enable_X11 := False; end if;
      if Cli_Debug_Events then Config.Log_Events := True; end if;
      if Cli_Debug_Cpu then Config.Debug_Cpu := True; end if;
      if Cli_Debug_Fake then Config.Debug_Fake_Input := True; end if;
      if Cli_Stats then Config.Log_Stats := True; else Config.Log_Stats := False; end if;
      if Cli_Audio_Null then Config.Audio_Backend := To_Unbounded_String ("null"); end if;
      if Cli_Audio_Bell then Config.Audio_Backend := To_Unbounded_String ("bell"); end if;
      if Cli_Silent then
         Config.Audio_Backend := To_Unbounded_String ("null");
         Config.Log_Events := False;
         Config.Log_Stats := False;
         Config.Debug_Cpu := False;
         Config.Debug_Fake_Input := False;
      end if;
      Config.Engine.Ambient_Level := Config.Ambient_Level;
      Config.Engine.Burst_Density := Config.Burst_Density;
   end Apply_Cli_Overrides;

   procedure Reload_Config_From_Disk (Config : in out Beep.Config.App_Config; Is_Reload : Boolean) is
      Base : Beep.Config.App_Config := Beep.Config.With_Profile (Beep.Config.Defaults, "normal");
      Old_Backend : constant String := To_String (Config.Audio_Backend);
   begin
      if Ada.Directories.Exists (To_String (Config_Path)) then
         begin
            Base := Beep.Config.Load_File (To_String (Config_Path), Base);
         exception
            when E : others =>
               Log_Warn ("reload failed for config " & To_String (Config_Path) & ": " & Ada.Exceptions.Exception_Message (E));
         end;
      end if;

      if Cli_Profile /= Null_Unbounded_String then
         Base := Beep.Config.With_Profile (Base, To_String (Cli_Profile));
      end if;
      Apply_Cli_Overrides (Base);
      Config := Base;
      Beep.Audio.Reconfigure (Audio_Engine, Config);
      if Is_Reload then
         Log_Info ("[info] config reloaded from " & To_String (Config_Path));
      end if;
      if Is_Reload and then To_String (Config.Audio_Backend) /= Old_Backend then
         Log_Warn ("audio backend change requires restart");
      end if;
   end Reload_Config_From_Disk;

begin
   for I in 1 .. Ada.Command_Line.Argument_Count loop
      declare
         Arg : constant String := Ada.Command_Line.Argument (I);
         V1  : constant String := Value_Flag (Arg, "--config=");
         V2  : constant String := Value_Flag (Arg, "--profile=");
         Recognized : Boolean := False;
      begin
         if V1 /= "" then
            Config_Path := To_Unbounded_String (V1);
            Recognized := True;
         end if;

         if V2 /= "" then
            Cli_Profile := To_Unbounded_String (V2);
            Recognized := True;
         end if;

         if Arg = "--help" or else Arg = "-h" then
            Print_Usage;
            Cleanup;
            return;
         elsif Arg = "--version" or else Arg = "-V" then
            Ada.Text_IO.Put_Line ("beep 0.1.0-dev");
            Cleanup;
            return;
         elsif Arg = "--quiet" or else Arg = "-q" then
            Cli_Quiet := True; Recognized := True;
         elsif Arg = "--verbose" or else Arg = "-v" then
            Cli_Verbose := True; Recognized := True;
         elsif Arg = "--silent" or else Arg = "-s" then
            Cli_Silent := True; Recognized := True;
         elsif Arg = "--no-cpu" then
            Cli_No_Cpu := True; Recognized := True;
         elsif Arg = "--no-system" then
            Cli_No_System := True; Recognized := True;
         elsif Arg = "--no-net" then
            Cli_No_Net := True; Recognized := True;
         elsif Arg = "--no-x11" then
            Cli_No_X11 := True; Recognized := True;
         elsif Arg = "--debug-events" then
            Cli_Debug_Events := True; Recognized := True;
         elsif Arg = "--debug-cpu" then
            Cli_Debug_Cpu := True; Recognized := True;
         elsif Arg = "--debug-fake-input" then
            Cli_Debug_Fake := True; Recognized := True;
         elsif Arg = "--stats" then
            Cli_Stats := True; Recognized := True;
         elsif Arg = "--audio-null" then
            Cli_Audio_Null := True; Recognized := True;
         elsif Arg = "--audio-bell" then
            Cli_Audio_Bell := True; Recognized := True;
         end if;

         if (not Recognized) and then Arg'Length > 0 and then Arg (Arg'First) = '-' then
            Ada.Text_IO.Put_Line ("[error] unknown flag: " & Arg);
            Print_Usage;
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            Cleanup;
            return;
         end if;
      end;
   end loop;

   if Cli_Silent then
      Cli_Quiet := True;
      Cli_Debug_Events := False;
      Cli_Stats := False;
   end if;

   Reload_Config_From_Disk (Cfg, Is_Reload => False);

   Log_Info ("profile=" & To_String (Cfg.Profile)
      & " config=" & To_String (Config_Path)
      & " audio=" & To_String (Cfg.Audio_Backend));
   Log_Info ("sources: cpu=" & Boolean'Image (Cfg.Enable_Cpu)
      & " system=" & Boolean'Image (Cfg.Enable_System)
      & " net=" & Boolean'Image (Cfg.Enable_Network)
      & " x11=" & Boolean'Image (Cfg.Enable_X11));

   Beep.Linux.Samplers.Initialize (Cpu_Sampler, Sys_Sampler, Net_Sampler, X11_Sampler);
   Beep.Audio.Initialize (Audio_Engine, Cfg);
   Beep.Runtime.Signals.Install;
   Log_Info ("audio-backend=" & Beep.Audio.Backend_Name (Audio_Engine));
   if Cfg.Enable_X11 and then not Beep.Linux.Samplers.X11_Active (X11_Sampler) then
      Log_Warn ("X11 sampler unavailable (no display or X11 access)");
   end if;
   declare
      Session_Type    : constant String := Ada.Characters.Handling.To_Lower (Ada.Environment_Variables.Value ("XDG_SESSION_TYPE", ""));
      Wayland_Display : constant String := Ada.Environment_Variables.Value ("WAYLAND_DISPLAY", "");
   begin
      Wayland_Session := Session_Type = "wayland" or else Wayland_Display /= "";
      if Wayland_Session and then (not Cfg.Enable_X11 or else not Beep.Linux.Samplers.X11_Active (X11_Sampler)) then
         Log_Warn ("Wayland session detected without active interactive input stream; activity feel may be less responsive");
      end if;
   end;

   Log_Info ("beep sampler loop started. Ctrl+C to stop.");
   Startup_Ts := Beep.Linux.Samplers.Now_Ms;
   while not Stop_Requested loop
      declare
         Ts : constant Milliseconds := Beep.Linux.Samplers.Now_Ms;
         Reload_Now : Boolean := False;
         Stop_Now   : Boolean := False;
      begin
         Beep.Runtime.Signals.Poll (Reload_Now, Stop_Now);
         if Reload_Now then
            Reload_Config_From_Disk (Cfg, Is_Reload => True);
         end if;
         if Stop_Now then
            Stop_Requested := True;
            exit;
         end if;

         if Cfg.Enable_Cpu then
            declare
                  Sample : constant Beep.Linux.Samplers.Optional_Activity_Sample :=
                 Beep.Linux.Samplers.Poll_Cpu (Cpu_Sampler, Cfg.Engine, Cfg.Debug_Cpu, Ts);
            begin
               if Beep.Linux.Samplers.Has_Value (Sample) then
                  Handle_Sample (Mapper_State, Audio_Engine, Cfg, Last_By_Kind, Event_Counts, Beep.Linux.Samplers.Value (Sample));
               end if;
            end;
         end if;

         if Cfg.Enable_System then
            declare
               Batch : constant Beep.Linux.Samplers.Activity_Batch :=
                 Beep.Linux.Samplers.Poll_System (Sys_Sampler, Ts);
            begin
               for I in 1 .. Beep.Linux.Samplers.Count (Batch) loop
                  Handle_Sample (Mapper_State, Audio_Engine, Cfg, Last_By_Kind, Event_Counts, Beep.Linux.Samplers.Item (Batch, I));
               end loop;
            end;
         end if;

         if Cfg.Enable_Network then
            declare
                  Sample : constant Beep.Linux.Samplers.Optional_Activity_Sample :=
                 Beep.Linux.Samplers.Poll_Net (Net_Sampler, Ts);
            begin
               if Beep.Linux.Samplers.Has_Value (Sample) then
                  Handle_Sample (Mapper_State, Audio_Engine, Cfg, Last_By_Kind, Event_Counts, Beep.Linux.Samplers.Value (Sample));
               end if;
            end;
         end if;

         if Cfg.Enable_X11 then
            declare
               Batch : constant Beep.Linux.Samplers.Activity_Batch :=
                 Beep.Linux.Samplers.Poll_X11 (X11_Sampler, Ts);
            begin
               for I in 1 .. Beep.Linux.Samplers.Count (Batch) loop
                  X11_Seen_Input := True;
                  Handle_Sample (Mapper_State, Audio_Engine, Cfg, Last_By_Kind, Event_Counts, Beep.Linux.Samplers.Item (Batch, I));
               end loop;
            end;
         end if;

         if Wayland_Session
           and then Cfg.Enable_X11
           and then Beep.Linux.Samplers.X11_Active (X11_Sampler)
           and then not X11_Seen_Input
           and then not X11_No_Input_Warned
           and then Ts - Startup_Ts >= 15_000
         then
            Log_Warn ("no X11 keyboard/mouse activity observed on Wayland after 15s; interactive tuning may be incomplete");
            X11_No_Input_Warned := True;
         end if;

         if Cfg.Log_Stats then
            if Stats_Window_Start = 0 then
               Stats_Window_Start := Ts;
            elsif Ts - Stats_Window_Start >= Milliseconds (Cfg.Stats_Interval_Ms) then
               Emit_Stats (Event_Counts, Ts - Stats_Window_Start, Ts);
               Event_Counts := (others => 0);
               Stats_Window_Start := Ts;
            end if;
         end if;
      end;

      delay 0.04;
   end loop;

   Cleanup;
exception
   when E : others =>
      Cleanup;
      Ada.Text_IO.Put_Line ("[error] beep main failed: " & Ada.Exceptions.Exception_Message (E));
      raise;
end Main;
