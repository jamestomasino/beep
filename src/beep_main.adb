with Ada.Command_Line;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Beep.Audio;
with Beep.Config;
with Beep.Core.Mapping;
with Beep.Core.Types;
with Beep.Linux.Samplers;

procedure Beep_Main is
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

   function Has_Flag (Flag : String) return Boolean is
   begin
      for I in 1 .. Ada.Command_Line.Argument_Count loop
         if Ada.Command_Line.Argument (I) = Flag then
            return True;
         end if;
      end loop;
      return False;
   end Has_Flag;

   procedure Print_Usage is
      use Ada.Text_IO;
   begin
      Put_Line ("beep - activity sonifier CLI (Ada migration)");
      Put_Line ("flags:");
      Put_Line ("  --config=<path>");
      Put_Line ("  --profile=<calm|normal|noisy>");
      Put_Line ("  --no-cpu");
      Put_Line ("  --no-system");
      Put_Line ("  --no-net");
      Put_Line ("  --no-x11");
      Put_Line ("  --debug-events");
      Put_Line ("  --debug-cpu");
      Put_Line ("  --debug-fake-input");
      Put_Line ("  --audio-null");
      Put_Line ("  --audio-bell");
      Put_Line ("  --help");
   end Print_Usage;

   procedure Handle_Sample
     (State  : in out Engine_State;
      Audio  : in out Beep.Audio.Audio_Engine;
      Cfg    : Beep.Config.App_Config;
      Sample : Activity_Sample)
   is
      Event : Optional_Sound_Event := Beep.Core.Mapping.Map_Activity (State, Cfg.Engine, Sample);
   begin
      if Event.Has_Value then
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
   Cli_Audio_Null   : Boolean := False;
   Cli_Audio_Bell   : Boolean := False;

   Mapper_State : Engine_State := New_State;
   Cpu_Sampler  : Beep.Linux.Samplers.Cpu_Sampler;
   Sys_Sampler  : Beep.Linux.Samplers.System_Sampler;
   Net_Sampler  : Beep.Linux.Samplers.Net_Sampler;
   X11_Sampler  : Beep.Linux.Samplers.X11_Sampler;
   Audio_Engine : Beep.Audio.Audio_Engine;

begin
   if Has_Flag ("--help") or else Has_Flag ("-h") then
      Print_Usage;
      return;
   end if;

   for I in 1 .. Ada.Command_Line.Argument_Count loop
      declare
         Arg : constant String := Ada.Command_Line.Argument (I);
         V1  : constant String := Value_Flag (Arg, "--config=");
         V2  : constant String := Value_Flag (Arg, "--profile=");
      begin
         if V1 /= "" then
            Config_Path := To_Unbounded_String (V1);
         end if;

         if V2 /= "" then
            Cli_Profile := To_Unbounded_String (V2);
         end if;

         if Arg = "--no-cpu" then Cli_No_Cpu := True; end if;
         if Arg = "--no-system" then Cli_No_System := True; end if;
         if Arg = "--no-net" then Cli_No_Net := True; end if;
         if Arg = "--no-x11" then Cli_No_X11 := True; end if;
         if Arg = "--debug-events" then Cli_Debug_Events := True; end if;
         if Arg = "--debug-cpu" then Cli_Debug_Cpu := True; end if;
         if Arg = "--debug-fake-input" then Cli_Debug_Fake := True; end if;
         if Arg = "--audio-null" then Cli_Audio_Null := True; end if;
         if Arg = "--audio-bell" then Cli_Audio_Bell := True; end if;
      end;
   end loop;

   if Ada.Directories.Exists (To_String (Config_Path)) then
      begin
         Cfg := Beep.Config.Load_File (To_String (Config_Path), Cfg);
      exception
         when E : others =>
            Ada.Text_IO.Put_Line ("[warn] could not parse config " & To_String (Config_Path) & ": " & Ada.Exceptions.Exception_Message (E));
      end;
   end if;

   if Cli_Profile /= Null_Unbounded_String then
      Cfg := Beep.Config.With_Profile (Cfg, To_String (Cli_Profile));
   end if;

   if Cli_No_Cpu then Cfg.Enable_Cpu := False; end if;
   if Cli_No_System then Cfg.Enable_System := False; end if;
   if Cli_No_Net then Cfg.Enable_Network := False; end if;
   if Cli_No_X11 then Cfg.Enable_X11 := False; end if;
   if Cli_Debug_Events then Cfg.Log_Events := True; end if;
   if Cli_Debug_Cpu then Cfg.Debug_Cpu := True; end if;
   if Cli_Debug_Fake then Cfg.Debug_Fake_Input := True; end if;
   if Cli_Audio_Null then Cfg.Audio_Backend := To_Unbounded_String ("null"); end if;
   if Cli_Audio_Bell then Cfg.Audio_Backend := To_Unbounded_String ("bell"); end if;
   Cfg.Engine.Ambient_Level := Cfg.Ambient_Level;
   Cfg.Engine.Burst_Density := Cfg.Burst_Density;

   Ada.Text_IO.Put_Line ("profile=" & To_String (Cfg.Profile)
      & " config=" & To_String (Config_Path)
      & " audio=" & To_String (Cfg.Audio_Backend));
   Ada.Text_IO.Put_Line ("sources: cpu=" & Boolean'Image (Cfg.Enable_Cpu)
      & " system=" & Boolean'Image (Cfg.Enable_System)
      & " net=" & Boolean'Image (Cfg.Enable_Network)
      & " x11=" & Boolean'Image (Cfg.Enable_X11));

   Beep.Linux.Samplers.Initialize (Cpu_Sampler, Sys_Sampler, Net_Sampler, X11_Sampler);
   Beep.Audio.Initialize (Audio_Engine, Cfg);
   Ada.Text_IO.Put_Line ("audio-backend=" & Beep.Audio.Backend_Name (Audio_Engine));
   if Cfg.Enable_X11 and then not Beep.Linux.Samplers.X11_Active (X11_Sampler) then
      Ada.Text_IO.Put_Line ("[warn] X11 sampler unavailable (no display or X11 access)");
   end if;

   Ada.Text_IO.Put_Line ("beep sampler loop started. Ctrl+C to stop.");
   loop
      declare
         Ts : constant Milliseconds := Beep.Linux.Samplers.Now_Ms;
      begin
         if Cfg.Enable_Cpu then
            declare
                  Sample : constant Beep.Linux.Samplers.Optional_Activity_Sample :=
                 Beep.Linux.Samplers.Poll_Cpu (Cpu_Sampler, Cfg.Engine, Cfg.Debug_Cpu, Ts);
            begin
               if Beep.Linux.Samplers.Has_Value (Sample) then
                  Handle_Sample (Mapper_State, Audio_Engine, Cfg, Beep.Linux.Samplers.Value (Sample));
               end if;
            end;
         end if;

         if Cfg.Enable_System then
            declare
               Batch : constant Beep.Linux.Samplers.Activity_Batch :=
                 Beep.Linux.Samplers.Poll_System (Sys_Sampler, Ts);
            begin
               for I in 1 .. Beep.Linux.Samplers.Count (Batch) loop
                  Handle_Sample (Mapper_State, Audio_Engine, Cfg, Beep.Linux.Samplers.Item (Batch, I));
               end loop;
            end;
         end if;

         if Cfg.Enable_Network then
            declare
                  Sample : constant Beep.Linux.Samplers.Optional_Activity_Sample :=
                 Beep.Linux.Samplers.Poll_Net (Net_Sampler, Ts);
            begin
               if Beep.Linux.Samplers.Has_Value (Sample) then
                  Handle_Sample (Mapper_State, Audio_Engine, Cfg, Beep.Linux.Samplers.Value (Sample));
               end if;
            end;
         end if;

         if Cfg.Enable_X11 then
            declare
               Batch : constant Beep.Linux.Samplers.Activity_Batch :=
                 Beep.Linux.Samplers.Poll_X11 (X11_Sampler, Ts);
            begin
               for I in 1 .. Beep.Linux.Samplers.Count (Batch) loop
                  Handle_Sample (Mapper_State, Audio_Engine, Cfg, Beep.Linux.Samplers.Item (Batch, I));
               end loop;
            end;
         end if;
      end;

      delay 0.04;
   end loop;
end Beep_Main;
