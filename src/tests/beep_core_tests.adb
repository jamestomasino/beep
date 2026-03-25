with Ada.Exceptions;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Beep.Core.Mapping;
with Beep.Core.Types;

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

begin
   Test_Keyboard_Threshold;
   Test_Deterministic_Seeded_Output;
   Test_Min_Gap_Enforced;
   Put_Line ("beep_core_tests: OK");
exception
   when E : others =>
      Put_Line ("beep_core_tests: FAIL: " & Ada.Exceptions.Exception_Message (E));
      raise;
end Beep_Core_Tests;
