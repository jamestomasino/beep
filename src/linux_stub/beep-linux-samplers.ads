with Beep.Core.Types;
with Interfaces;
with Interfaces.C;
with System;

package Beep.Linux.Samplers is
   type Cpu_Sampler is private;
   type System_Sampler is private;
   type Net_Sampler is private;
   type X11_Sampler is private;

   type Optional_Activity_Sample is private;
   type Activity_Batch is private;

   procedure Initialize
     (Cpu    : out Cpu_Sampler;
      Sys    : out System_Sampler;
      Net    : out Net_Sampler;
      X11    : out X11_Sampler);

   procedure Shutdown (Sampler : in out X11_Sampler);

   function Poll_Cpu
     (Sampler   : in out Cpu_Sampler;
      Cfg       : Beep.Core.Types.Engine_Config;
      Debug     : Boolean;
      Timestamp : Beep.Core.Types.Milliseconds) return Optional_Activity_Sample;

   function Poll_System
     (Sampler   : in out System_Sampler;
      Timestamp : Beep.Core.Types.Milliseconds) return Activity_Batch;

   function Poll_Net
     (Sampler   : in out Net_Sampler;
      Timestamp : Beep.Core.Types.Milliseconds) return Optional_Activity_Sample;

   function Poll_X11
     (Sampler   : in out X11_Sampler;
      Timestamp : Beep.Core.Types.Milliseconds) return Activity_Batch;

   function X11_Active (Sampler : X11_Sampler) return Boolean;

   function Has_Value (Sample : Optional_Activity_Sample) return Boolean;
   function Value (Sample : Optional_Activity_Sample) return Beep.Core.Types.Activity_Sample
     with Pre => Has_Value (Sample);

   function Count (Batch : Activity_Batch) return Natural;
   function Item (Batch : Activity_Batch; Index : Positive) return Beep.Core.Types.Activity_Sample
     with Pre => Index <= Count (Batch);

   function Now_Ms return Beep.Core.Types.Milliseconds;

private
   use Beep.Core.Types;

   type Cpu_Sampler is null record;
   type System_Sampler is null record;
   type Net_Sampler is null record;
   type X11_Sampler is null record;

   type Optional_Activity_Sample is record
      Has : Boolean := False;
      Val : Activity_Sample;
   end record;

   type Activity_Batch is record
      N      : Natural range 0 .. 6 := 0;
      Item_1 : Activity_Sample;
      Item_2 : Activity_Sample;
      Item_3 : Activity_Sample;
      Item_4 : Activity_Sample;
      Item_5 : Activity_Sample;
      Item_6 : Activity_Sample;
   end record;
end Beep.Linux.Samplers;
