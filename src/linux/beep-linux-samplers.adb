with Ada.Calendar;
with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Strings.Unbounded.Text_IO;
with Ada.Text_IO;
with Interfaces;
with Interfaces.C;
with Interfaces.C.Strings;
with System;

package body Beep.Linux.Samplers is
   use Ada.Strings.Unbounded;
   use Beep.Core.Types;
   use Interfaces;
   use Interfaces.C;
   use type System.Address;

   Epoch : constant Ada.Calendar.Time := Ada.Calendar.Time_Of (1970, 1, 1, 0.0);

   type X_Window is new unsigned_long;
   subtype C_Int is Interfaces.C.int;
   subtype C_UInt is Interfaces.C.unsigned;

   function XOpenDisplay (Name : Interfaces.C.Strings.chars_ptr) return System.Address
     with Import, Convention => C, External_Name => "XOpenDisplay";
   function XCloseDisplay (Dpy : System.Address) return C_Int
     with Import, Convention => C, External_Name => "XCloseDisplay";
   function XDefaultRootWindow (Dpy : System.Address) return X_Window
     with Import, Convention => C, External_Name => "XDefaultRootWindow";
   function XQueryPointer
     (Dpy          : System.Address;
      W            : X_Window;
      Root_Return  : access X_Window;
      Child_Return : access X_Window;
      Root_X       : access C_Int;
      Root_Y       : access C_Int;
      Win_X        : access C_Int;
      Win_Y        : access C_Int;
      Mask_Return  : access C_UInt) return C_Int
     with Import, Convention => C, External_Name => "XQueryPointer";
   function XQueryKeymap (Dpy : System.Address; Keys_Return : System.Address) return C_Int
     with Import, Convention => C, External_Name => "XQueryKeymap";

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
            Intensity  => Intensity,
            Timestamp  => Timestamp,
            Source     => To_Unbounded_String (Source),
            Cpu_Bucket => Bucket
         )
      );
   end Make_Optional;

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

   function Abs_I (Value : C_Int) return C_Int is
   begin
      if Value < 0 then
         return -Value;
      else
         return Value;
      end if;
   end Abs_I;

   function Popcount8 (Value : Unsigned_8) return Natural is
      Count : Natural := 0;
      V     : Unsigned_8 := Value;
   begin
      while V /= 0 loop
         Count := Count + 1;
         V := V and (V - 1);
      end loop;
      return Count;
   end Popcount8;

   function Is_Space (C : Character) return Boolean is
   begin
      return C <= ' ';
   end Is_Space;

   function Starts_With (Text : String; Prefix : String) return Boolean is
   begin
      return Text'Length >= Prefix'Length
        and then Text (Text'First .. Text'First + Prefix'Length - 1) = Prefix;
   end Starts_With;

   function Nth_Field (Line : String; N : Positive) return String is
      I     : Integer := Line'First;
      Count : Natural := 0;
      Start : Integer;
   begin
      while I <= Line'Last loop
         while I <= Line'Last and then Is_Space (Line (I)) loop
            I := I + 1;
         end loop;
         exit when I > Line'Last;

         Start := I;
         while I <= Line'Last and then not Is_Space (Line (I)) loop
            I := I + 1;
         end loop;

         Count := Count + 1;
         if Count = N then
            return Line (Start .. I - 1);
         end if;
      end loop;
      return "";
   end Nth_Field;

   function To_U64 (Text : String; Ok : out Boolean) return Unsigned_64 is
   begin
      Ok := True;
      return Unsigned_64'Value (Text);
   exception
      when others =>
         Ok := False;
         return 0;
   end To_U64;

   function To_Float (Text : String; Ok : out Boolean) return Float is
   begin
      Ok := True;
      return Float'Value (Text);
   exception
      when others =>
         Ok := False;
         return 0.0;
   end To_Float;

   function Read_Cpu_Totals (Total : out Unsigned_64; Idle_Val : out Unsigned_64) return Boolean is
      File   : Ada.Text_IO.File_Type;
      Line_U : Unbounded_String;
      N      : Positive := 2;
      Value  : Unsigned_64;
      Ok     : Boolean;
   begin
      Total := 0;
      Idle_Val := 0;

      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, "/proc/stat");
      while not Ada.Text_IO.End_Of_File (File) loop
         Ada.Strings.Unbounded.Text_IO.Get_Line (File, Line_U);
         declare
            Line : constant String := To_String (Line_U);
         begin
            if Starts_With (Line, "cpu ") then
               loop
                  declare
                     Field : constant String := Nth_Field (Line, N);
                  begin
                     exit when Field = "";
                     Value := To_U64 (Field, Ok);
                     if not Ok then
                        Ada.Text_IO.Close (File);
                        return False;
                     end if;
                     Total := Total + Value;
                     if N = 5 then
                        Idle_Val := Value;
                     end if;
                     N := N + 1;
                  end;
               end loop;
               Ada.Text_IO.Close (File);
               return N > 5;
            end if;
         end;
      end loop;
      Ada.Text_IO.Close (File);
      return False;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         return False;
   end Read_Cpu_Totals;

   function Read_Stat_Counter (Key : String; Value : out Unsigned_64) return Boolean is
      File   : Ada.Text_IO.File_Type;
      Line_U : Unbounded_String;
      Ok     : Boolean;
   begin
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, "/proc/stat");
      while not Ada.Text_IO.End_Of_File (File) loop
         Ada.Strings.Unbounded.Text_IO.Get_Line (File, Line_U);
         declare
            Line   : constant String := To_String (Line_U);
            Field2 : constant String := Nth_Field (Line, 2);
         begin
            if Starts_With (Line, Key) then
               if Field2 = "" then
                  Ada.Text_IO.Close (File);
                  return False;
               end if;
               Value := To_U64 (Field2, Ok);
               Ada.Text_IO.Close (File);
               return Ok;
            end if;
         end;
      end loop;
      Ada.Text_IO.Close (File);
      return False;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         return False;
   end Read_Stat_Counter;

   function Read_Mem_Ratio (Ratio : out Float) return Boolean is
      File      : Ada.Text_IO.File_Type;
      Line_U    : Unbounded_String;
      Mem_Total : Float := 0.0;
      Mem_Avail : Float := 0.0;
      Ok        : Boolean;
   begin
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, "/proc/meminfo");
      while not Ada.Text_IO.End_Of_File (File) loop
         Ada.Strings.Unbounded.Text_IO.Get_Line (File, Line_U);
         declare
            Line : constant String := To_String (Line_U);
         begin
            if Starts_With (Line, "MemTotal:") then
               Mem_Total := To_Float (Nth_Field (Line, 2), Ok);
               if not Ok then
                  Mem_Total := 0.0;
               end if;
            elsif Starts_With (Line, "MemAvailable:") then
               Mem_Avail := To_Float (Nth_Field (Line, 2), Ok);
               if not Ok then
                  Mem_Avail := 0.0;
               end if;
            end if;
         end;
      end loop;
      Ada.Text_IO.Close (File);

      if Mem_Total <= 0.0 then
         return False;
      end if;

      Ratio := Clamp01 (1.0 - (Mem_Avail / Mem_Total));
      return True;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         return False;
   end Read_Mem_Ratio;

   function Read_System_Snapshot (Snap : out System_Snapshot) return Boolean is
      Procs : Unsigned_64;
      Ctxt  : Unsigned_64;
      Mem   : Float;
   begin
      if not Read_Stat_Counter ("processes", Procs) then
         return False;
      end if;
      if not Read_Stat_Counter ("ctxt", Ctxt) then
         return False;
      end if;
      if not Read_Mem_Ratio (Mem) then
         return False;
      end if;

      Snap := (
         Processes_Total => Procs,
         Ctxt_Total      => Ctxt,
         Mem_Used_Ratio  => Mem
      );
      return True;
   end Read_System_Snapshot;

   function Read_Net_Snapshot (Snap : out Net_Snapshot) return Boolean is
      File     : Ada.Text_IO.File_Type;
      Line_U   : Unbounded_String;
      Rx_Total : Unsigned_64 := 0;
      Tx_Total : Unsigned_64 := 0;
   begin
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, "/proc/net/dev");
      while not Ada.Text_IO.End_Of_File (File) loop
         Ada.Strings.Unbounded.Text_IO.Get_Line (File, Line_U);
         declare
            Trimmed : constant String := Ada.Strings.Fixed.Trim (To_String (Line_U), Ada.Strings.Both);
         begin
            if Trimmed = ""
              or else Starts_With (Trimmed, "Inter-")
              or else Starts_With (Trimmed, "face")
            then
               null;
            else
               declare
                  Sanitized : String := Trimmed;
               begin
                  for I in Sanitized'Range loop
                     if Sanitized (I) = ':' then
                        Sanitized (I) := ' ';
                     end if;
                  end loop;

                  declare
                     Iface    : constant String := Nth_Field (Sanitized, 1);
                     Rx_Field : constant String := Nth_Field (Sanitized, 2);
                     Tx_Field : constant String := Nth_Field (Sanitized, 10);
                     Ok       : Boolean;
                     Rx       : Unsigned_64;
                     Tx       : Unsigned_64;
                  begin
                     if Iface /= ""
                       and then Iface /= "lo"
                       and then Nth_Field (Sanitized, 17) /= ""
                       and then Rx_Field /= ""
                       and then Tx_Field /= ""
                     then
                        Rx := To_U64 (Rx_Field, Ok);
                        if Ok then
                           Tx := To_U64 (Tx_Field, Ok);
                           if Ok then
                              Rx_Total := Rx_Total + Rx;
                              Tx_Total := Tx_Total + Tx;
                           end if;
                        end if;
                     end if;
                  end;
               end;
            end if;
         end;
      end loop;
      Ada.Text_IO.Close (File);

      Snap := (Rx_Bytes => Rx_Total, Tx_Bytes => Tx_Total);
      return True;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         return False;
   end Read_Net_Snapshot;

   procedure Add_Sample (Batch : in out Activity_Batch; Sample : Activity_Sample) is
   begin
      if Batch.N < 3 then
         Batch.N := Batch.N + 1;
         case Batch.N is
            when 1 => Batch.Item_1 := Sample;
            when 2 => Batch.Item_2 := Sample;
            when 3 => Batch.Item_3 := Sample;
            when others => null;
         end case;
      end if;
   end Add_Sample;

   procedure Initialize
     (Cpu    : out Cpu_Sampler;
      Sys    : out System_Sampler;
      Net    : out Net_Sampler;
      X11    : out X11_Sampler)
   is
   begin
      Cpu := (others => <>);
      Sys := (others => <>);
      Net := (others => <>);

      X11 := (others => <>);
      X11.Display := XOpenDisplay (Interfaces.C.Strings.Null_Ptr);
      if X11.Display /= System.Null_Address then
         declare
            Root : constant X_Window := XDefaultRootWindow (X11.Display);
         begin
            X11.Root := unsigned_long (Root);
            X11.Is_Available := True;
         end;
      end if;
   end Initialize;

   procedure Shutdown (Sampler : in out X11_Sampler) is
      Ignore : C_Int;
   begin
      if Sampler.Display /= System.Null_Address then
         Ignore := XCloseDisplay (Sampler.Display);
         pragma Unreferenced (Ignore);
      end if;
      Sampler := (others => <>);
   end Shutdown;

   function Poll_Cpu
     (Sampler   : in out Cpu_Sampler;
      Cfg       : Engine_Config;
      Debug     : Boolean;
      Timestamp : Milliseconds) return Optional_Activity_Sample
   is
      Total       : Unsigned_64;
      Idle_Val    : Unsigned_64;
      Delta_Total : Unsigned_64;
      Delta_Idle  : Unsigned_64;
      Used        : Unsigned_64;
      Util        : Float;
      Bucket      : Cpu_Bucket;
   begin
      if not Read_Cpu_Totals (Total, Idle_Val) then
         return Make_Optional_None;
      end if;

      if not Sampler.Primed then
         Sampler.Prev_Total := Total;
         Sampler.Prev_Idle := Idle_Val;
         Sampler.Primed := True;
         return Make_Optional_None;
      end if;

      if Total < Sampler.Prev_Total or else Idle_Val < Sampler.Prev_Idle then
         Sampler.Prev_Total := Total;
         Sampler.Prev_Idle := Idle_Val;
         return Make_Optional_None;
      end if;

      Delta_Total := Total - Sampler.Prev_Total;
      Delta_Idle := Idle_Val - Sampler.Prev_Idle;

      Sampler.Prev_Total := Total;
      Sampler.Prev_Idle := Idle_Val;

      if Delta_Total = 0 then
         return Make_Optional_None;
      end if;

      Used := Delta_Total - Delta_Idle;
      Util := Float (Used) / Float (Delta_Total);

      if Util >= Cfg.Cpu_Busy_Cutoff then
         Bucket := Busy;
      elsif Util >= Cfg.Cpu_Active_Cutoff then
         Bucket := Active;
      else
         Bucket := Idle;
      end if;

      if Debug then
         Ada.Text_IO.Put_Line ("[cpu] util=" & Float'Image (Util));
      end if;

      return Make_Optional (Cpu, Util, Timestamp, "linux.proc.stat", Bucket);
   end Poll_Cpu;

   function Poll_System
     (Sampler   : in out System_Sampler;
      Timestamp : Milliseconds) return Activity_Batch
   is
      Batch      : Activity_Batch := (N => 0, Item_1 => Empty_Sample, Item_2 => Empty_Sample, Item_3 => Empty_Sample);
      Next       : System_Snapshot;
      Proc_Delta : Unsigned_64;
      Ctxt_Delta : Unsigned_64;
      Mem_Delta  : Float;
      Intensity  : Float;
   begin
      if not Read_System_Snapshot (Next) then
         return Batch;
      end if;

      if not Sampler.Primed then
         Sampler.Prev := Next;
         Sampler.Primed := True;
         return Batch;
      end if;

      if Next.Processes_Total >= Sampler.Prev.Processes_Total then
         Proc_Delta := Next.Processes_Total - Sampler.Prev.Processes_Total;
      else
         Proc_Delta := 0;
      end if;

      if Proc_Delta > 0 then
         Intensity := Clamp01 (Float (Proc_Delta) / 12.0);
         Add_Sample
           (Batch,
            (Kind => Process, Intensity => Intensity, Timestamp => Timestamp,
             Source => To_Unbounded_String ("linux.proc.processes"), Cpu_Bucket => Idle));
      end if;

      if Next.Ctxt_Total >= Sampler.Prev.Ctxt_Total then
         Ctxt_Delta := Next.Ctxt_Total - Sampler.Prev.Ctxt_Total;
      else
         Ctxt_Delta := 0;
      end if;

      if Ctxt_Delta > 0 then
         Intensity := Float (Ctxt_Delta) / 60000.0;
         if Intensity > 0.08 then
            Add_Sample
              (Batch,
               (Kind => Beep.Core.Types.System, Intensity => Clamp01 (Intensity), Timestamp => Timestamp,
                Source => To_Unbounded_String ("linux.proc.ctxt"), Cpu_Bucket => Idle));
         end if;
      end if;

      Mem_Delta := Next.Mem_Used_Ratio - Sampler.Prev.Mem_Used_Ratio;
      if Mem_Delta < 0.0 then
         Mem_Delta := -Mem_Delta;
      end if;

      if Mem_Delta > 0.006 then
         Intensity := Clamp01 (Mem_Delta * 45.0);
         Add_Sample
           (Batch,
            (Kind => Memory, Intensity => Intensity, Timestamp => Timestamp,
             Source => To_Unbounded_String ("linux.proc.mem"), Cpu_Bucket => Idle));
      end if;

      Sampler.Prev := Next;
      return Batch;
   end Poll_System;

   function Poll_Net
     (Sampler   : in out Net_Sampler;
      Timestamp : Milliseconds) return Optional_Activity_Sample
   is
      Next      : Net_Snapshot;
      Rx_Delta  : Unsigned_64;
      Tx_Delta  : Unsigned_64;
      Total     : Unsigned_64;
      Bps       : Float;
      Intensity : Float;
   begin
      if not Read_Net_Snapshot (Next) then
         return Make_Optional_None;
      end if;

      if not Sampler.Primed then
         Sampler.Prev := Next;
         Sampler.Primed := True;
         return Make_Optional_None;
      end if;

      if Next.Rx_Bytes >= Sampler.Prev.Rx_Bytes then
         Rx_Delta := Next.Rx_Bytes - Sampler.Prev.Rx_Bytes;
      else
         Rx_Delta := 0;
      end if;

      if Next.Tx_Bytes >= Sampler.Prev.Tx_Bytes then
         Tx_Delta := Next.Tx_Bytes - Sampler.Prev.Tx_Bytes;
      else
         Tx_Delta := 0;
      end if;

      Total := Rx_Delta + Tx_Delta;
      Sampler.Prev := Next;

      if Total = 0 then
         return Make_Optional_None;
      end if;

      Bps := Float (Total) * (1000.0 / 350.0);
      Intensity := Clamp01 (Bps / 262_144.0);

      return Make_Optional (Network, Intensity, Timestamp, "linux.proc.net", Idle);
   end Poll_Net;

   function Poll_X11
     (Sampler   : in out X11_Sampler;
      Timestamp : Milliseconds) return Activity_Batch
   is
      Batch       : Activity_Batch := (N => 0, Item_1 => Empty_Sample, Item_2 => Empty_Sample, Item_3 => Empty_Sample);
      Root_Ret    : aliased X_Window := 0;
      Child_Ret   : aliased X_Window := 0;
      Root_X      : aliased C_Int := 0;
      Root_Y      : aliased C_Int := 0;
      Win_X       : aliased C_Int := 0;
      Win_Y       : aliased C_Int := 0;
      Mask_Ret    : aliased C_UInt := 0;
      Pointer_Ok  : C_Int;
      Current_Map : Keymap_Bits := (others => 0);
      Keys_Ok     : C_Int;
      Delta_Mouse : C_Int := 0;
      Key_Changes : Natural := 0;
   begin
      if not Sampler.Is_Available or else Sampler.Display = System.Null_Address then
         return Batch;
      end if;

      Pointer_Ok :=
        XQueryPointer
          (Sampler.Display,
           X_Window (Sampler.Root),
           Root_Ret'Access,
           Child_Ret'Access,
           Root_X'Access,
           Root_Y'Access,
           Win_X'Access,
           Win_Y'Access,
           Mask_Ret'Access);
      Keys_Ok := XQueryKeymap (Sampler.Display, Current_Map'Address);
      if Pointer_Ok = 0 or else Keys_Ok = 0 then
         Sampler.Is_Available := False;
         return Batch;
      end if;

      if not Sampler.Primed then
         Sampler.Prev_Root_X := Root_X;
         Sampler.Prev_Root_Y := Root_Y;
         Sampler.Prev_Keymap := Current_Map;
         Sampler.Primed := True;
         return Batch;
      end if;

      Delta_Mouse := Abs_I (Root_X - Sampler.Prev_Root_X) + Abs_I (Root_Y - Sampler.Prev_Root_Y);
      if Delta_Mouse > 0 then
         Add_Sample
           (Batch,
            (Kind => Mouse,
             Intensity => Clamp01 (Float (Delta_Mouse) / 160.0),
             Timestamp => Timestamp,
             Source => To_Unbounded_String ("linux.x11.pointer.move"),
             Cpu_Bucket => Idle));
      end if;

      for I in Current_Map'Range loop
         Key_Changes := Key_Changes + Popcount8 (Current_Map (I) xor Sampler.Prev_Keymap (I));
      end loop;

      if Key_Changes > 0 then
         Add_Sample
           (Batch,
            (Kind => Keyboard,
             Intensity => Clamp01 (Float (Key_Changes) / 6.0),
             Timestamp => Timestamp,
             Source => To_Unbounded_String ("linux.x11.keyboard"),
             Cpu_Bucket => Idle));
      end if;

      Sampler.Prev_Root_X := Root_X;
      Sampler.Prev_Root_Y := Root_Y;
      Sampler.Prev_Keymap := Current_Map;
      return Batch;
   end Poll_X11;

   function X11_Active (Sampler : X11_Sampler) return Boolean is
   begin
      return Sampler.Is_Available;
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
         when others => return Empty_Sample;
      end case;
   end Item;

   function Now_Ms return Milliseconds is
      Now_Time : constant Ada.Calendar.Time := Ada.Calendar.Clock;
      Elapsed  : constant Duration := Ada.Calendar."-" (Now_Time, Epoch);
   begin
      return Milliseconds (Long_Long_Integer (Elapsed * 1000.0));
   end Now_Ms;
end Beep.Linux.Samplers;
