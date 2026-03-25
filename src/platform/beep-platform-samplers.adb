with Ada.Calendar;
with Ada.Strings.Unbounded;
with Beep.Platform.Samplers.Darwin;
with Beep.Platform.Samplers.Linux;

package body Beep.Platform.Samplers is
   use Beep.Core.Types;

   Epoch : constant Ada.Calendar.Time := Ada.Calendar.Time_Of (1970, 1, 1, 0.0);

   function Empty_Sample return Activity_Sample is
   begin
      return (
         Kind       => Cpu,
         Intensity  => 0.0,
         Timestamp  => 0,
         Source     => Ada.Strings.Unbounded.Null_Unbounded_String,
         Cpu_Bucket => Idle
      );
   end Empty_Sample;

   function Is_Darwin return Boolean is
   begin
      return Beep.Platform.Samplers.Darwin.Available;
   end Is_Darwin;

   function Is_Linux return Boolean is
   begin
      return Beep.Platform.Samplers.Linux.Available;
   end Is_Linux;

   procedure Initialize
     (Cpu    : out Cpu_Sampler;
      Sys    : out System_Sampler;
      Net    : out Net_Sampler;
      X11    : out X11_Sampler)
   is
   begin
      if Is_Linux then
         Beep.Platform.Samplers.Linux.Initialize (Cpu, Sys, Net, X11);
      elsif Is_Darwin then
         Beep.Platform.Samplers.Darwin.Initialize (Cpu, Sys, Net, X11);
      else
         Cpu := (others => <>);
         Sys := (others => <>);
         Net := (others => <>);
         X11 := (others => <>);
      end if;
   end Initialize;

   procedure Shutdown (Sampler : in out X11_Sampler) is
   begin
      if Is_Linux then
         Beep.Platform.Samplers.Linux.Shutdown (Sampler);
      elsif Is_Darwin then
         Beep.Platform.Samplers.Darwin.Shutdown (Sampler);
      end if;
   end Shutdown;

   function Poll_Cpu
     (Sampler   : in out Cpu_Sampler;
      Cfg       : Engine_Config;
      Debug     : Boolean;
      Timestamp : Milliseconds) return Optional_Activity_Sample
   is
   begin
      if Is_Linux then
         return Beep.Platform.Samplers.Linux.Poll_Cpu (Sampler, Cfg, Debug, Timestamp);
      elsif Is_Darwin then
         return Beep.Platform.Samplers.Darwin.Poll_Cpu (Sampler, Cfg, Debug, Timestamp);
      end if;
      return (Has => False, Val => Empty_Sample);
   end Poll_Cpu;

   function Poll_System
     (Sampler   : in out System_Sampler;
      Timestamp : Milliseconds) return Activity_Batch
   is
   begin
      if Is_Linux then
         return Beep.Platform.Samplers.Linux.Poll_System (Sampler, Timestamp);
      elsif Is_Darwin then
         return Beep.Platform.Samplers.Darwin.Poll_System (Sampler, Timestamp);
      end if;
      return
        (N => 0,
         Item_1 => Empty_Sample,
         Item_2 => Empty_Sample,
         Item_3 => Empty_Sample,
         Item_4 => Empty_Sample,
         Item_5 => Empty_Sample,
         Item_6 => Empty_Sample);
   end Poll_System;

   function Poll_Net
     (Sampler   : in out Net_Sampler;
      Timestamp : Milliseconds) return Optional_Activity_Sample
   is
   begin
      if Is_Linux then
         return Beep.Platform.Samplers.Linux.Poll_Net (Sampler, Timestamp);
      elsif Is_Darwin then
         return Beep.Platform.Samplers.Darwin.Poll_Net (Sampler, Timestamp);
      end if;
      return (Has => False, Val => Empty_Sample);
   end Poll_Net;

   function Poll_X11
     (Sampler   : in out X11_Sampler;
      Timestamp : Milliseconds) return Activity_Batch
   is
   begin
      if Is_Linux then
         return Beep.Platform.Samplers.Linux.Poll_X11 (Sampler, Timestamp);
      elsif Is_Darwin then
         return Beep.Platform.Samplers.Darwin.Poll_X11 (Sampler, Timestamp);
      end if;
      return
        (N => 0,
         Item_1 => Empty_Sample,
         Item_2 => Empty_Sample,
         Item_3 => Empty_Sample,
         Item_4 => Empty_Sample,
         Item_5 => Empty_Sample,
         Item_6 => Empty_Sample);
   end Poll_X11;

   function X11_Active (Sampler : X11_Sampler) return Boolean is
   begin
      if Is_Linux then
         return Beep.Platform.Samplers.Linux.X11_Active (Sampler);
      elsif Is_Darwin then
         return Beep.Platform.Samplers.Darwin.X11_Active (Sampler);
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
