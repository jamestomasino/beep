with Ada.Calendar;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Beep.Linux.Samplers;
with Interfaces.C;
with Interfaces.C.Strings;

package body Beep.Platform.Samplers is
   use Ada.Strings.Unbounded;
   use Beep.Core.Types;

   Epoch : constant Ada.Calendar.Time := Ada.Calendar.Time_Of (1970, 1, 1, 0.0);

   Running_Darwin : constant Boolean := Ada.Directories.Exists ("/System/Library/Sounds");
   Running_Linux  : constant Boolean := (not Running_Darwin) and then Ada.Directories.Exists ("/proc");

   function C_System (Command : Interfaces.C.Strings.chars_ptr) return Interfaces.C.int
     with Import, Convention => C, External_Name => "system";

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

   function Empty_Sample return Activity_Sample is
   begin
      return (
         Kind       => Cpu,
         Intensity  => 0.0,
         Timestamp  => 0,
         Source     => To_Unbounded_String (""),
         Cpu_Bucket => Idle
      );
   end Empty_Sample;

   function Make_Optional_None return Optional_Activity_Sample is
   begin
      return (Has => False, Val => Empty_Sample);
   end Make_Optional_None;

   function Make_Optional
     (Kind      : Activity_Kind;
      Intensity : Float;
      Timestamp : Milliseconds;
      Source    : String;
      Bucket    : Cpu_Bucket := Idle) return Optional_Activity_Sample
   is
   begin
      return (
         Has => True,
         Val => (
            Kind       => Kind,
            Intensity  => Clamp01 (Intensity),
            Timestamp  => Timestamp,
            Source     => To_Unbounded_String (Source),
            Cpu_Bucket => Bucket
         )
      );
   end Make_Optional;

   procedure Add_Sample (Batch : in out Activity_Batch; Sample : Activity_Sample) is
   begin
      if Batch.N < 6 then
         Batch.N := Batch.N + 1;
         case Batch.N is
            when 1 => Batch.Item_1 := Sample;
            when 2 => Batch.Item_2 := Sample;
            when 3 => Batch.Item_3 := Sample;
            when 4 => Batch.Item_4 := Sample;
            when 5 => Batch.Item_5 := Sample;
            when 6 => Batch.Item_6 := Sample;
            when others => null;
         end case;
      end if;
   end Add_Sample;

   function Shell_Output (Command : String) return String is
      Tmp_Path : constant String := "/tmp/beep-sampler.out";
      Full_Cmd : constant String := "/bin/sh -c '" & Command & " > " & Tmp_Path & " 2>/dev/null'";
      Cmd_Ptr  : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.Null_Ptr;
      Rc       : Interfaces.C.int := 0;
      File     : Ada.Text_IO.File_Type;
      Content  : Unbounded_String := Null_Unbounded_String;
   begin
      Cmd_Ptr := Interfaces.C.Strings.New_String (Full_Cmd);
      Rc := C_System (Cmd_Ptr);
      pragma Unreferenced (Rc);
      Interfaces.C.Strings.Free (Cmd_Ptr);

      begin
         Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Tmp_Path);
      exception
         when others =>
            return "";
      end;

      while not Ada.Text_IO.End_Of_File (File) loop
         declare
            Line : constant String := Ada.Text_IO.Get_Line (File);
         begin
            if Content = Null_Unbounded_String then
               Content := To_Unbounded_String (Line);
            else
               Content := Content & ASCII.LF & Line;
            end if;
         end;
      end loop;
      Ada.Text_IO.Close (File);
      return To_String (Content);
   end Shell_Output;

   function Parse_First_I64 (Text : String; Value : out Long_Long_Integer) return Boolean is
      I     : Integer := Text'First;
      Sign  : Long_Long_Integer := 1;
      Found : Boolean := False;
      Acc   : Long_Long_Integer := 0;
   begin
      while I <= Text'Last and then Text (I) = ' ' loop
         I := I + 1;
      end loop;
      if I <= Text'Last and then Text (I) = '-' then
         Sign := -1;
         I := I + 1;
      end if;
      while I <= Text'Last and then Text (I) in '0' .. '9' loop
         Found := True;
         Acc := Acc * 10 + Long_Long_Integer (Character'Pos (Text (I)) - Character'Pos ('0'));
         I := I + 1;
      end loop;
      if Found then
         Value := Acc * Sign;
      end if;
      return Found;
   end Parse_First_I64;

   function Parse_First_Float (Text : String; Value : out Float) return Boolean is
      use Ada.Strings;
      use Ada.Strings.Fixed;
      Start : Integer := Text'First;
      Stop  : Integer := Text'First - 1;
   begin
      while Start <= Text'Last loop
         exit when Text (Start) in '-' | '+' | '.' | '0' .. '9';
         Start := Start + 1;
      end loop;
      if Start > Text'Last then
         return False;
      end if;
      Stop := Start;
      while Stop <= Text'Last and then Text (Stop) in '-' | '+' | '.' | '0' .. '9' | 'e' | 'E' loop
         Stop := Stop + 1;
      end loop;
      begin
         Value := Float'Value (Trim (Text (Start .. Stop - 1), Both));
         return True;
      exception
         when others =>
            return False;
      end;
   end Parse_First_Float;

   function Parse_Nth_I64 (Text : String; N : Positive; Value : out Long_Long_Integer) return Boolean is
      I     : Integer := Text'First;
      Count : Natural := 0;
      Start : Integer;
   begin
      while I <= Text'Last loop
         while I <= Text'Last and then not (Text (I) in '-' | '0' .. '9') loop
            I := I + 1;
         end loop;
         exit when I > Text'Last;

         Start := I;
         if Text (I) = '-' then
            I := I + 1;
         end if;
         while I <= Text'Last and then Text (I) in '0' .. '9' loop
            I := I + 1;
         end loop;

         Count := Count + 1;
         if Count = N then
            return Parse_First_I64 (Text (Start .. I - 1), Value);
         end if;
      end loop;
      return False;
   end Parse_Nth_I64;

   function Token_Count (Line : String) return Natural is
      I : Integer := Line'First;
      N : Natural := 0;
   begin
      while I <= Line'Last loop
         while I <= Line'Last and then Line (I) <= ' ' loop
            I := I + 1;
         end loop;
         exit when I > Line'Last;
         N := N + 1;
         while I <= Line'Last and then Line (I) > ' ' loop
            I := I + 1;
         end loop;
      end loop;
      return N;
   end Token_Count;

   function Nth_Token (Line : String; N : Positive) return String is
      I     : Integer := Line'First;
      Count : Natural := 0;
      Start : Integer;
   begin
      while I <= Line'Last loop
         while I <= Line'Last and then Line (I) <= ' ' loop
            I := I + 1;
         end loop;
         exit when I > Line'Last;
         Start := I;
         while I <= Line'Last and then Line (I) > ' ' loop
            I := I + 1;
         end loop;
         Count := Count + 1;
         if Count = N then
            return Line (Start .. I - 1);
         end if;
      end loop;
      return "";
   end Nth_Token;

   function Is_Digit_String (Text : String) return Boolean is
   begin
      if Text'Length = 0 then
         return False;
      end if;
      for C of Text loop
         if C not in '0' .. '9' then
            return False;
         end if;
      end loop;
      return True;
   end Is_Digit_String;

   function Parse_Darwin_Memory_Used (Text : String) return Float is
      use Ada.Strings;
      use Ada.Strings.Fixed;
      Marker : constant String := "System-wide memory free percentage";
      Pos    : constant Natural := Index (Text, Marker);
      Free_Pct : Float := 0.0;
   begin
      if Pos > 0 and then Parse_First_Float (Text (Pos .. Text'Last), Free_Pct) then
         return Clamp01 ((100.0 - Free_Pct) / 100.0);
      end if;
      return 0.0;
   end Parse_Darwin_Memory_Used;

   procedure Parse_Darwin_Net_Totals
     (Text : String;
      Rx   : out Long_Long_Integer;
      Tx   : out Long_Long_Integer)
   is
      I       : Integer := Text'First;
      Sum_Rx  : Long_Long_Integer := 0;
      Sum_Tx  : Long_Long_Integer := 0;
   begin
      while I <= Text'Last loop
         declare
            Start : constant Integer := I;
         begin
            while I <= Text'Last and then Text (I) /= ASCII.LF loop
               I := I + 1;
            end loop;
            if I > Start then
               declare
                  Line    : constant String := Text (Start .. I - 1);
                  Cnt     : constant Natural := Token_Count (Line);
                  Iface   : constant String := Nth_Token (Line, 1);
                  In_Byte : constant String := (if Cnt >= 12 then Nth_Token (Line, 11) else "");
                  Out_Byte: constant String := (if Cnt >= 12 then Nth_Token (Line, 12) else "");
                  In_V    : Long_Long_Integer := 0;
                  Out_V   : Long_Long_Integer := 0;
               begin
                  if Cnt >= 12 and then Iface /= "Name" and then Iface /= "lo0"
                    and then Is_Digit_String (In_Byte) and then Is_Digit_String (Out_Byte)
                    and then Parse_First_I64 (In_Byte, In_V) and then Parse_First_I64 (Out_Byte, Out_V)
                  then
                     Sum_Rx := Sum_Rx + In_V;
                     Sum_Tx := Sum_Tx + Out_V;
                  end if;
               end;
            end if;
            I := I + 1;
         end;
      end loop;
      Rx := Sum_Rx;
      Tx := Sum_Tx;
   end Parse_Darwin_Net_Totals;

   function Darwin_Hid_Idle_Ns (Value : out Long_Long_Integer) return Boolean is
      Dump : constant String := Shell_Output ("/usr/sbin/ioreg -c IOHIDSystem -r -d 1");
      use Ada.Strings;
      use Ada.Strings.Fixed;
      Pos  : constant Natural := Index (Dump, "HIDIdleTime");
   begin
      Value := 0;
      if Pos = 0 then
         return False;
      end if;
      return Parse_First_I64 (Dump (Pos .. Dump'Last), Value);
   end Darwin_Hid_Idle_Ns;

   function Is_Darwin return Boolean is
   begin
      return Running_Darwin;
   end Is_Darwin;

   function Is_Linux return Boolean is
   begin
      return Running_Linux;
   end Is_Linux;

   procedure Initialize
     (Cpu    : out Cpu_Sampler;
      Sys    : out System_Sampler;
      Net    : out Net_Sampler;
      X11    : out X11_Sampler)
   is
      LCpu : Beep.Linux.Samplers.Cpu_Sampler;
      LSys : Beep.Linux.Samplers.System_Sampler;
      LNet : Beep.Linux.Samplers.Net_Sampler;
      LX11 : Beep.Linux.Samplers.X11_Sampler;
   begin
      Beep.Linux.Samplers.Initialize (LCpu, LSys, LNet, LX11);
      Cpu := (Linux => LCpu, others => <>);
      Sys := (Linux => LSys, others => <>);
      Net := (Linux => LNet, others => <>);
      X11 := (Linux => LX11, others => <>);
      if Running_Darwin then
         declare
            Idle_Ns : Long_Long_Integer := 0;
         begin
            X11.Darwin_Active := Darwin_Hid_Idle_Ns (Idle_Ns);
            X11.Prev_Idle_Ns := Idle_Ns;
            X11.Primed := X11.Darwin_Active;
         end;
      end if;
   end Initialize;

   procedure Shutdown (Sampler : in out X11_Sampler) is
   begin
      Beep.Linux.Samplers.Shutdown (Sampler.Linux);
   end Shutdown;

   function Poll_Cpu
     (Sampler   : in out Cpu_Sampler;
      Cfg       : Engine_Config;
      Debug     : Boolean;
      Timestamp : Milliseconds) return Optional_Activity_Sample
   is
   begin
      if Running_Linux then
         declare
            S : constant Beep.Linux.Samplers.Optional_Activity_Sample :=
              Beep.Linux.Samplers.Poll_Cpu (Sampler.Linux, Cfg, Debug, Timestamp);
         begin
            if Beep.Linux.Samplers.Has_Value (S) then
               return (Has => True, Val => Beep.Linux.Samplers.Value (S));
            end if;
            return Make_Optional_None;
         end;
      end if;

      if Running_Darwin then
         declare
            Cpu_Text : constant String := Shell_Output ("/usr/sbin/sysctl -n kern.cp_time");
            User_T   : Long_Long_Integer := 0;
            Nice_T   : Long_Long_Integer := 0;
            Sys_T    : Long_Long_Integer := 0;
            Idle_T   : Long_Long_Integer := 0;
            Intr_T   : Long_Long_Integer := 0;
            Total    : Long_Long_Integer := 0;
            Delta_T  : Long_Long_Integer := 0;
            Delta_I  : Long_Long_Integer := 0;
            Util     : Float := 0.0;
            Bucket   : Cpu_Bucket := Idle;
         begin
            if not Parse_Nth_I64 (Cpu_Text, 1, User_T)
              or else not Parse_Nth_I64 (Cpu_Text, 2, Nice_T)
              or else not Parse_Nth_I64 (Cpu_Text, 3, Sys_T)
              or else not Parse_Nth_I64 (Cpu_Text, 4, Idle_T)
              or else not Parse_Nth_I64 (Cpu_Text, 5, Intr_T)
            then
               return Make_Optional_None;
            end if;

            Total := User_T + Nice_T + Sys_T + Idle_T + Intr_T;
            if not Sampler.Primed then
               Sampler.Prev_Total := Total;
               Sampler.Prev_Idle := Idle_T;
               Sampler.Primed := True;
               return Make_Optional_None;
            end if;

            Delta_T := Total - Sampler.Prev_Total;
            Delta_I := Idle_T - Sampler.Prev_Idle;
            Sampler.Prev_Total := Total;
            Sampler.Prev_Idle := Idle_T;

            if Delta_T <= 0 then
               return Make_Optional_None;
            end if;

            Util := Clamp01 (Float (Delta_T - Delta_I) / Float (Delta_T));
            if Util >= Cfg.Cpu_Busy_Cutoff then
               Bucket := Busy;
            elsif Util >= Cfg.Cpu_Active_Cutoff then
               Bucket := Active;
            end if;

            if Debug then
               Ada.Text_IO.Put_Line ("[cpu] util=" & Float'Image (Util));
            end if;

            return Make_Optional (Cpu, Util, Timestamp, "darwin.sysctl.cp_time", Bucket);
         end;
      end if;

      return Make_Optional_None;
   end Poll_Cpu;

   function Poll_System
     (Sampler   : in out System_Sampler;
      Timestamp : Milliseconds) return Activity_Batch
   is
      Batch : Activity_Batch := (N => 0, Item_1 => Empty_Sample, Item_2 => Empty_Sample, Item_3 => Empty_Sample, Item_4 => Empty_Sample, Item_5 => Empty_Sample, Item_6 => Empty_Sample);
   begin
      if Running_Linux then
         declare
            LB : constant Beep.Linux.Samplers.Activity_Batch := Beep.Linux.Samplers.Poll_System (Sampler.Linux, Timestamp);
         begin
            for I in 1 .. Beep.Linux.Samplers.Count (LB) loop
               Add_Sample (Batch, Beep.Linux.Samplers.Item (LB, I));
            end loop;
            return Batch;
         end;
      end if;

      if Running_Darwin then
         declare
            Processes_Text : constant String := Shell_Output ("/bin/ps -A -o pid= | /usr/bin/wc -l");
            Memory_Text    : constant String := Shell_Output ("/usr/bin/memory_pressure -Q");
            Load_Text      : constant String := Shell_Output ("/usr/sbin/sysctl -n vm.loadavg");
            Proc_Now       : Long_Long_Integer := 0;
            Mem_Now        : Float := 0.0;
            Load_Now       : Float := 0.0;
            Delta_Proc     : Long_Long_Integer := 0;
            Delta_Mem      : Float := 0.0;
            Delta_Load     : Float := 0.0;
         begin
            if not Parse_First_I64 (Processes_Text, Proc_Now) then
               Proc_Now := 0;
            end if;
            Mem_Now := Parse_Darwin_Memory_Used (Memory_Text);
            if not Parse_First_Float (Load_Text, Load_Now) then
               Load_Now := 0.0;
            end if;

            if not Sampler.Primed then
               Sampler.Prev_Processes := Proc_Now;
               Sampler.Prev_Memory_Used := Mem_Now;
               Sampler.Prev_Load_1 := Load_Now;
               Sampler.Primed := True;
               return Batch;
            end if;

            Delta_Proc := Proc_Now - Sampler.Prev_Processes;
            if Delta_Proc > 0 then
               Add_Sample
                 (Batch,
                  (Kind => Process,
                   Intensity => Clamp01 (Float (Delta_Proc) / 10.0),
                   Timestamp => Timestamp,
                   Source => To_Unbounded_String ("darwin.ps.processes"),
                   Cpu_Bucket => Idle));
            end if;

            Delta_Mem := Mem_Now - Sampler.Prev_Memory_Used;
            if Delta_Mem < 0.0 then
               Delta_Mem := -Delta_Mem;
            end if;
            if Delta_Mem > 0.006 then
               Add_Sample
                 (Batch,
                  (Kind => Memory,
                   Intensity => Clamp01 (Delta_Mem * 18.0),
                   Timestamp => Timestamp,
                   Source => To_Unbounded_String ("darwin.memory_pressure"),
                   Cpu_Bucket => Idle));
            end if;

            Delta_Load := Load_Now - Sampler.Prev_Load_1;
            if Delta_Load < 0.0 then
               Delta_Load := -Delta_Load;
            end if;
            if Delta_Load > 0.02 or else Load_Now > 1.5 then
               Add_Sample
                 (Batch,
                  (Kind => Beep.Core.Types.System,
                   Intensity => Clamp01 (Delta_Load * 3.0 + (Load_Now / 8.0)),
                   Timestamp => Timestamp,
                   Source => To_Unbounded_String ("darwin.sysctl.loadavg"),
                   Cpu_Bucket => Idle));
            end if;

            Sampler.Prev_Processes := Proc_Now;
            Sampler.Prev_Memory_Used := Mem_Now;
            Sampler.Prev_Load_1 := Load_Now;
            return Batch;
         end;
      end if;

      return Batch;
   end Poll_System;

   function Poll_Net
     (Sampler   : in out Net_Sampler;
      Timestamp : Milliseconds) return Optional_Activity_Sample
   is
   begin
      if Running_Linux then
         declare
            S : constant Beep.Linux.Samplers.Optional_Activity_Sample :=
              Beep.Linux.Samplers.Poll_Net (Sampler.Linux, Timestamp);
         begin
            if Beep.Linux.Samplers.Has_Value (S) then
               return (Has => True, Val => Beep.Linux.Samplers.Value (S));
            end if;
            return Make_Optional_None;
         end;
      end if;

      if Running_Darwin then
         declare
            Net_Text : constant String := Shell_Output ("/usr/sbin/netstat -ibn");
            Rx_Now   : Long_Long_Integer := 0;
            Tx_Now   : Long_Long_Integer := 0;
            Delta_Rx : Long_Long_Integer := 0;
            Delta_Tx : Long_Long_Integer := 0;
            Total    : Long_Long_Integer := 0;
         begin
            Parse_Darwin_Net_Totals (Net_Text, Rx_Now, Tx_Now);
            if Rx_Now = 0 and then Tx_Now = 0 then
               return Make_Optional_None;
            end if;

            if not Sampler.Primed then
               Sampler.Prev_Rx := Rx_Now;
               Sampler.Prev_Tx := Tx_Now;
               Sampler.Primed := True;
               return Make_Optional_None;
            end if;

            Delta_Rx := Rx_Now - Sampler.Prev_Rx;
            Delta_Tx := Tx_Now - Sampler.Prev_Tx;
            if Delta_Rx < 0 then Delta_Rx := 0; end if;
            if Delta_Tx < 0 then Delta_Tx := 0; end if;
            Total := Delta_Rx + Delta_Tx;

            Sampler.Prev_Rx := Rx_Now;
            Sampler.Prev_Tx := Tx_Now;

            if Total = 0 then
               return Make_Optional_None;
            end if;

            return Make_Optional
              (Network,
               Clamp01 (Float (Total) / 524_288.0),
               Timestamp,
               "darwin.netstat.bytes",
               Idle);
         end;
      end if;

      return Make_Optional_None;
   end Poll_Net;

   function Poll_X11
     (Sampler   : in out X11_Sampler;
      Timestamp : Milliseconds) return Activity_Batch
   is
      Batch : Activity_Batch := (N => 0, Item_1 => Empty_Sample, Item_2 => Empty_Sample, Item_3 => Empty_Sample, Item_4 => Empty_Sample, Item_5 => Empty_Sample, Item_6 => Empty_Sample);
   begin
      if Running_Linux then
         declare
            LB : constant Beep.Linux.Samplers.Activity_Batch := Beep.Linux.Samplers.Poll_X11 (Sampler.Linux, Timestamp);
         begin
            for I in 1 .. Beep.Linux.Samplers.Count (LB) loop
               Add_Sample (Batch, Beep.Linux.Samplers.Item (LB, I));
            end loop;
            return Batch;
         end;
      end if;

      if Running_Darwin then
         declare
            Idle_Ns : Long_Long_Integer := 0;
         begin
            if not Darwin_Hid_Idle_Ns (Idle_Ns) then
               Sampler.Darwin_Active := False;
               return Batch;
            end if;

            Sampler.Darwin_Active := True;
            if not Sampler.Primed then
               Sampler.Prev_Idle_Ns := Idle_Ns;
               Sampler.Primed := True;
               return Batch;
            end if;

            --  HIDIdleTime resets downward when interactive input occurs.
            if Idle_Ns < Sampler.Prev_Idle_Ns then
               declare
                  Drop_Ns : constant Long_Long_Integer := Sampler.Prev_Idle_Ns - Idle_Ns;
                  K_Intensity : Float := Clamp01 (0.36 + Float (Drop_Ns) / 220_000_000.0);
                  M_Intensity : Float := Clamp01 (0.28 + Float (Drop_Ns) / 340_000_000.0);
               begin
                  Add_Sample
                    (Batch,
                     (Kind => Keyboard,
                      Intensity => K_Intensity,
                      Timestamp => Timestamp,
                      Source => To_Unbounded_String ("darwin.hid.keyboard"),
                      Cpu_Bucket => Idle));

                  Add_Sample
                    (Batch,
                     (Kind => Mouse,
                      Intensity => M_Intensity,
                      Timestamp => Timestamp,
                      Source => To_Unbounded_String ("darwin.hid.pointer"),
                      Cpu_Bucket => Idle));

                  Sampler.Last_Emit_Ms := Timestamp;
               end;
            elsif Idle_Ns < 260_000_000 and then (Sampler.Last_Emit_Ms = 0 or else Timestamp - Sampler.Last_Emit_Ms >= 140) then
               --  While user is actively interacting, keep a light follow-up stream.
               Add_Sample
                 (Batch,
                  (Kind => Keyboard,
                   Intensity => 0.34,
                   Timestamp => Timestamp,
                   Source => To_Unbounded_String ("darwin.hid.keyboard.continuous"),
                   Cpu_Bucket => Idle));
               Sampler.Last_Emit_Ms := Timestamp;
            end if;

            Sampler.Prev_Idle_Ns := Idle_Ns;
            return Batch;
         end;
      end if;

      pragma Unreferenced (Timestamp);
      return Batch;
   end Poll_X11;

   function X11_Active (Sampler : X11_Sampler) return Boolean is
   begin
      if Running_Linux then
         return Beep.Linux.Samplers.X11_Active (Sampler.Linux);
      elsif Running_Darwin then
         return Sampler.Darwin_Active;
      end if;
      return False;
   end X11_Active;

   function Has_Value (Sample : Optional_Activity_Sample) return Boolean is
   begin
      return Sample.Has;
   end Has_Value;

   function Value (Sample : Optional_Activity_Sample) return Activity_Sample is
   begin
      return Sample.Val;
   end Value;

   function Count (Batch : Activity_Batch) return Natural is
   begin
      return Batch.N;
   end Count;

   function Item (Batch : Activity_Batch; Index : Positive) return Activity_Sample is
   begin
      case Index is
         when 1 => return Batch.Item_1;
         when 2 => return Batch.Item_2;
         when 3 => return Batch.Item_3;
         when 4 => return Batch.Item_4;
         when 5 => return Batch.Item_5;
         when 6 => return Batch.Item_6;
         when others => return Empty_Sample;
      end case;
   end Item;

   function Now_Ms return Milliseconds is
      Now_Time : constant Ada.Calendar.Time := Ada.Calendar.Clock;
      Elapsed  : constant Duration := Ada.Calendar."-" (Now_Time, Epoch);
   begin
      return Milliseconds (Long_Long_Integer (Elapsed * 1000.0));
   end Now_Ms;
end Beep.Platform.Samplers;
