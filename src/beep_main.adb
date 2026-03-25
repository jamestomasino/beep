with Ada.Command_Line;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Beep.Config;

procedure Beep_Main is
   use Ada.Strings.Unbounded;

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
      Put_Line ("  --debug-events");
      Put_Line ("  --debug-cpu");
      Put_Line ("  --debug-fake-input");
      Put_Line ("  --audio-null");
      Put_Line ("  --help");
   end Print_Usage;

   Cfg                : Beep.Config.App_Config := Beep.Config.With_Profile (Beep.Config.Defaults, "normal");
   Config_Path        : Unbounded_String := To_Unbounded_String (Beep.Config.Default_Config_Path);
   Cli_Profile        : Unbounded_String := Null_Unbounded_String;
   Cli_No_Cpu         : Boolean := False;
   Cli_No_System      : Boolean := False;
   Cli_No_Net         : Boolean := False;
   Cli_Debug_Events   : Boolean := False;
   Cli_Debug_Cpu      : Boolean := False;
   Cli_Debug_Fake     : Boolean := False;
   Cli_Audio_Null     : Boolean := False;

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
         if Arg = "--debug-events" then Cli_Debug_Events := True; end if;
         if Arg = "--debug-cpu" then Cli_Debug_Cpu := True; end if;
         if Arg = "--debug-fake-input" then Cli_Debug_Fake := True; end if;
         if Arg = "--audio-null" then Cli_Audio_Null := True; end if;
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
   if Cli_Debug_Events then Cfg.Log_Events := True; end if;
   if Cli_Debug_Cpu then Cfg.Debug_Cpu := True; end if;
   if Cli_Debug_Fake then Cfg.Debug_Fake_Input := True; end if;
   if Cli_Audio_Null then Cfg.Audio_Backend := To_Unbounded_String ("null"); end if;

   Ada.Text_IO.Put_Line ("profile=" & To_String (Cfg.Profile)
      & " config=" & To_String (Config_Path)
      & " audio=" & To_String (Cfg.Audio_Backend));
   Ada.Text_IO.Put_Line ("sources: cpu=" & Boolean'Image (Cfg.Enable_Cpu)
      & " system=" & Boolean'Image (Cfg.Enable_System)
      & " net=" & Boolean'Image (Cfg.Enable_Network));
end Beep_Main;
