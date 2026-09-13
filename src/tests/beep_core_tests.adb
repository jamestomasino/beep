with Ada.Characters.Latin_1;
with Ada.Exceptions;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Beep.Core.Mapping;
with Beep.Core.Safety;
with Beep.Core.Types;
with Beep.Stdin;
with Interfaces.C;

procedure Beep_Core_Tests is
   use Ada.Strings.Unbounded;
   use Ada.Text_IO;
   use Beep.Core.Types;

   procedure Expect (Cond : Boolean; Msg : String) is
   begin
      if not Cond then
         raise Program_Error with Msg;
      end if;
   end Expect;

   procedure Test_Keyboard_Threshold is
      State  : Engine_State := New_State;
      Cfg    : Engine_Config := Default_Engine_Config;
      Sample : Activity_Sample := (
         Kind       => Keyboard,
         Intensity  => 0.10,
         Timestamp  => 1000,
         Source     => To_Unbounded_String ("linux.x11.keyboard"),
         Cpu_Bucket => Idle
      );
      Event : Optional_Sound_Event;
   begin
      Event := Beep.Core.Mapping.Map_Activity (State, Cfg, Sample);
      Expect (not Event.Has_Value, "keyboard below threshold should be dropped");
   end Test_Keyboard_Threshold;

   procedure Test_Deterministic_Seeded_Output is
      State_A : Engine_State := New_State;
      State_B : Engine_State := New_State;
      Cfg     : Engine_Config := Default_Engine_Config;
      Sample  : Activity_Sample := (
         Kind       => Keyboard,
         Intensity  => 0.92,
         Timestamp  => 2000,
         Source     => To_Unbounded_String ("linux.x11.keyboard"),
         Cpu_Bucket => Idle
      );
      A       : Optional_Sound_Event;
      B       : Optional_Sound_Event;
   begin
      A := Beep.Core.Mapping.Map_Activity (State_A, Cfg, Sample);
      B := Beep.Core.Mapping.Map_Activity (State_B, Cfg, Sample);

      Expect (A.Has_Value = B.Has_Value, "determinism mismatch on presence");
      if A.Has_Value and then B.Has_Value then
         Expect (A.Value.Motif = B.Value.Motif, "determinism mismatch on motif");
         Expect (abs (A.Value.Gain - B.Value.Gain) < 0.0001, "determinism mismatch on gain");
         Expect (A.Value.Duration_Ms = B.Value.Duration_Ms, "determinism mismatch on duration");
         Expect (To_String (A.Value.Reason) = To_String (B.Value.Reason), "determinism mismatch on reason");
      end if;
   end Test_Deterministic_Seeded_Output;

   procedure Test_Min_Gap_Enforced is
      State : Engine_State := New_State;
      Cfg   : Engine_Config := Default_Engine_Config;
      S1    : Activity_Sample := (
         Kind       => Mouse,
         Intensity  => 0.95,
         Timestamp  => 3000,
         Source     => To_Unbounded_String ("linux.x11.mouse.click"),
         Cpu_Bucket => Idle
      );
      S2    : Activity_Sample := (
         Kind       => Mouse,
         Intensity  => 0.95,
         Timestamp  => 3000,
         Source     => To_Unbounded_String ("linux.x11.mouse.click"),
         Cpu_Bucket => Idle
      );
      E1    : Optional_Sound_Event;
      E2    : Optional_Sound_Event;
   begin
      E1 := Beep.Core.Mapping.Map_Activity (State, Cfg, S1);
      E2 := Beep.Core.Mapping.Map_Activity (State, Cfg, S2);

      if E1.Has_Value then
         Expect (not E2.Has_Value, "second same-timestamp event should be blocked by gap");
      end if;
   end Test_Min_Gap_Enforced;

   procedure Test_Safety_Clamp is
      use Beep.Core.Safety;
   begin
      Expect (Clamp_Unit (-1.0) = 0.0, "Clamp_Unit low bound failed");
      Expect (Clamp_Unit (2.0) = 1.0, "Clamp_Unit high bound failed");
      Expect (Saturating_Scale (0.4, 2.0) = 0.8, "Saturating_Scale simple failed");
      Expect (Saturating_Scale (0.8, 2.0) = 1.0, "Saturating_Scale saturation failed");
   end Test_Safety_Clamp;

   --  Stdin is an event-driven trigger: one line in, one discrete hit out.
   procedure Test_Stdin_Low_Intensity_Dropped is
      State  : Engine_State := New_State;
      Cfg    : Engine_Config := Default_Engine_Config;
      Sample : Activity_Sample := (
         Kind       => Stdin,
         Intensity  => 0.03,
         Timestamp  => 1000,
         Source     => To_Unbounded_String ("log line"),
         Cpu_Bucket => Idle
      );
      Event  : Optional_Sound_Event;
   begin
      Event := Beep.Core.Mapping.Map_Activity (State, Cfg, Sample);
      Expect (not Event.Has_Value, "stdin below 0.05 should be dropped");
   end Test_Stdin_Low_Intensity_Dropped;

   procedure Test_Stdin_Discrete_Hit is
      State  : Engine_State := New_State;
      Cfg    : Engine_Config := Default_Engine_Config;
      Sample : Activity_Sample := (
         Kind       => Stdin,
         Intensity  => 1.0,
         Timestamp  => 2000,
         Source     => To_Unbounded_String ("INFO boot ok"),
         Cpu_Bucket => Idle
      );
      Event  : Optional_Sound_Event;
   begin
      Event := Beep.Core.Mapping.Map_Activity (State, Cfg, Sample);
      Expect (Event.Has_Value, "stdin at 1.0 should emit a hit");
      if Event.Has_Value then
         Expect (Event.Value.Gain >= 0.0 and then Event.Value.Gain <= 1.0,
                 "stdin gain out of [0,1]");
         Expect (Event.Value.Duration_Ms > 0, "stdin duration must be positive");
         --  Stdin must never become an ambient bed.
         Expect (Event.Value.Motif /= Drone
                 and then Event.Value.Motif /= Hum
                 and then Event.Value.Motif /= Pad,
                 "stdin must not emit an ambient motif");
      end if;
   end Test_Stdin_Discrete_Hit;

   procedure Test_Stdin_High_Intensity_Allows_Spark_Motifs is
      State  : Engine_State := New_State;
      Cfg    : Engine_Config := Default_Engine_Config;
      Sample : Activity_Sample := (
         Kind       => Stdin,
         Intensity  => 0.95,
         Timestamp  => 3000,
         Source     => To_Unbounded_String ("CRIT disk full"),
         Cpu_Bucket => Idle
      );
      Event  : Optional_Sound_Event;
   begin
      Event := Beep.Core.Mapping.Map_Activity (State, Cfg, Sample);
      Expect (Event.Has_Value, "stdin at 0.95 should emit a hit");
   end Test_Stdin_High_Intensity_Allows_Spark_Motifs;

   procedure Test_Stdin_Min_Gap_Enforced is
      State : Engine_State := New_State;
      Cfg   : Engine_Config := Default_Engine_Config;
      S1    : Activity_Sample := (
         Kind       => Stdin,
         Intensity  => 0.60,
         Timestamp  => 4000,
         Source     => To_Unbounded_String ("line A"),
         Cpu_Bucket => Idle
      );
      S2    : Activity_Sample := (
         Kind       => Stdin,
         Intensity  => 0.60,
         Timestamp  => 4000,
         Source     => To_Unbounded_String ("line B"),
         Cpu_Bucket => Idle
      );
      E1    : Optional_Sound_Event;
      E2    : Optional_Sound_Event;
   begin
      E1 := Beep.Core.Mapping.Map_Activity (State, Cfg, S1);
      E2 := Beep.Core.Mapping.Map_Activity (State, Cfg, S2);
      if E1.Has_Value then
         Expect (not E2.Has_Value, "second stdin event at same ts should be blocked by gap");
      end if;
   end Test_Stdin_Min_Gap_Enforced;

   --  Reader: self-contained. Writes a temp file, opens it via a C fd, and
   --  drives the reader on that fd with a 3-byte read chunk to force
   --  split-byte reassembly across reads. The three lines must arrive in order,
   --  each newline-stripped, and EOF must be observed after the last.
   procedure Test_Stdin_Reader is
      use Interfaces.C;
      --  int open(const char *path, int flags);
      function Open_File (Path  : access Character;
                          Flags : Interfaces.C.int) return Interfaces.C.int
         with Import, Convention => C, External_Name => "open";

      --  int close(int fd);
      function Close_Fd (Fd : Interfaces.C.int) return Interfaces.C.int
         with Import, Convention => C, External_Name => "close";

      --  ssize_t write(int fd, const void *buf, size_t count);
      function Write_Fd (Fd    : Interfaces.C.int;
                         Buf   : access Character;
                         Count : Interfaces.C.size_t) return Interfaces.C.long
         with Import, Convention => C, External_Name => "write";

      Path    : constant String := "beep_stdin_reader_test.tmp";
      Path_C  : array (1 .. Path'Length) of aliased Character;
      Fd      : Interfaces.C.int;
      R       : Beep.Stdin.Line_Reader;
      Line    : Unbounded_String;
      Have_Line : Boolean;
      Eof     : Boolean;
      Seen    : Natural := 0;
      LF      : constant Character := Character'Val (10);
      Payload : constant String := "alpha" & LF & "beta beta beta" & LF & "gamma" & LF;
      Payload_C : array (1 .. Payload'Length) of aliased Character;
      Wrote   : Interfaces.C.long;
      Closed  : Interfaces.C.int;
      --  O_RDWR(2) | O_CREAT(64) | O_TRUNC(512) = 578 (POSIX, same on darwin/linux).
      Open_Flags : constant Interfaces.C.int := 578;
      Rd_Flags   : constant Interfaces.C.int := 0;  -- O_RDONLY
   begin
      for I in 1 .. Path'Length loop
         Path_C (I) := Path (I);
      end loop;
      for I in 1 .. Payload'Length loop
         Payload_C (I) := Payload (I);
      end loop;

      Fd := Open_File (Path_C (1)'Access, Open_Flags);
      if Fd < 0 then
         Expect (False, "could not open temp file for reader test");
         return;
      end if;
      Wrote := Write_Fd (Fd, Payload_C (1)'Access,
                         Interfaces.C.size_t (Payload'Length));
      if Wrote /= Interfaces.C.long (Payload'Length) then
         Expect (False, "short write in reader test setup");
      end if;
      Closed := Close_Fd (Fd);

      Beep.Stdin.Initialize (R, Fd => Open_File (Path_C (1)'Access, Rd_Flags),
                             Read_Chunk => 3);

      loop
         Beep.Stdin.Poll (R, Line, Have_Line, Eof, Timeout_Ms => 200);
         exit when Eof;
         if Have_Line then
            Seen := Seen + 1;
            case Seen is
               when 1 => Expect (To_String (Line) = "alpha", "reader line 1 mismatch");
               when 2 => Expect (To_String (Line) = "beta beta beta", "reader line 2 mismatch");
               when 3 => Expect (To_String (Line) = "gamma", "reader line 3 mismatch");
               when others => Expect (False, "reader produced extra lines");
            end case;
         end if;
      end loop;

      Expect (Seen = 3, "reader should deliver exactly 3 lines (got " & Integer'Image (Seen) & ")");
   end Test_Stdin_Reader;

begin
   Test_Keyboard_Threshold;
   Test_Deterministic_Seeded_Output;
   Test_Min_Gap_Enforced;
   Test_Safety_Clamp;
   Test_Stdin_Low_Intensity_Dropped;
   Test_Stdin_Discrete_Hit;
   Test_Stdin_High_Intensity_Allows_Spark_Motifs;
   Test_Stdin_Min_Gap_Enforced;
   Test_Stdin_Reader;
   Put_Line ("beep_core_tests: OK");
exception
   when E : others =>
      Put_Line ("beep_core_tests: FAIL: " & Ada.Exceptions.Exception_Message (E));
      raise;
end Beep_Core_Tests;
