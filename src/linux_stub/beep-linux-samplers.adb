with Ada.Calendar;
with Ada.Strings.Unbounded;

package body Beep.Linux.Samplers is
   use Ada.Strings.Unbounded;
   use Beep.Core.Types;

   Epoch : constant Ada.Calendar.Time := Ada.Calendar.Time_Of (1970, 1, 1, 0.0);

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

   procedure Initialize
     (Cpu    : out Cpu_Sampler;
      Sys    : out System_Sampler;
      Net    : out Net_Sampler;
      X11    : out X11_Sampler) is
   begin
      Cpu := (null record);
      Sys := (null record);
      Net := (null record);
      X11 := (null record);
   end Initialize;

   procedure Shutdown (Sampler : in out X11_Sampler) is
   begin
      Sampler := (null record);
   end Shutdown;

   function Poll_Cpu
     (Sampler   : in out Cpu_Sampler;
      Cfg       : Engine_Config;
      Debug     : Boolean;
      Timestamp : Milliseconds) return Optional_Activity_Sample
   is
   begin
      pragma Unreferenced (Sampler, Cfg, Debug, Timestamp);
      return (Has => False, Val => Empty_Sample);
   end Poll_Cpu;

   function Poll_System
     (Sampler   : in out System_Sampler;
      Timestamp : Milliseconds) return Activity_Batch
   is
   begin
      pragma Unreferenced (Sampler, Timestamp);
      return (N => 0, Item_1 => Empty_Sample, Item_2 => Empty_Sample, Item_3 => Empty_Sample, Item_4 => Empty_Sample, Item_5 => Empty_Sample, Item_6 => Empty_Sample);
   end Poll_System;

   function Poll_Net
     (Sampler   : in out Net_Sampler;
      Timestamp : Milliseconds) return Optional_Activity_Sample
   is
   begin
      pragma Unreferenced (Sampler, Timestamp);
      return (Has => False, Val => Empty_Sample);
   end Poll_Net;

   function Poll_X11
     (Sampler   : in out X11_Sampler;
      Timestamp : Milliseconds) return Activity_Batch
   is
   begin
      pragma Unreferenced (Sampler, Timestamp);
      return (N => 0, Item_1 => Empty_Sample, Item_2 => Empty_Sample, Item_3 => Empty_Sample, Item_4 => Empty_Sample, Item_5 => Empty_Sample, Item_6 => Empty_Sample);
   end Poll_X11;

   function X11_Active (Sampler : X11_Sampler) return Boolean is
   begin
      pragma Unreferenced (Sampler);
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
end Beep.Linux.Samplers;
