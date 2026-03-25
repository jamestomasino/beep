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
   function Value (Sample : Optional_Activity_Sample) return Beep.Core.Types.Activity_Sample;

   function Count (Batch : Activity_Batch) return Natural;
   function Item (Batch : Activity_Batch; Index : Positive) return Beep.Core.Types.Activity_Sample;

   function Now_Ms return Beep.Core.Types.Milliseconds;

private
   use Beep.Core.Types;
   use Interfaces;

   type Cpu_Sampler is record
      Prev_Total : Unsigned_64 := 0;
      Prev_Idle  : Unsigned_64 := 0;
      Primed     : Boolean := False;
   end record;

   type System_Snapshot is record
      Processes_Total : Unsigned_64 := 0;
      Ctxt_Total      : Unsigned_64 := 0;
      Mem_Used_Ratio  : Float := 0.0;
   end record;

   type System_Sampler is record
      Prev   : System_Snapshot;
      Primed : Boolean := False;
   end record;

   type Net_Snapshot is record
      Rx_Bytes : Unsigned_64 := 0;
      Tx_Bytes : Unsigned_64 := 0;
   end record;

   type Net_Sampler is record
      Prev   : Net_Snapshot;
      Primed : Boolean := False;
   end record;

   type Keymap_Bits is array (Natural range 0 .. 31) of Interfaces.Unsigned_8;

   type X11_Sampler is record
      Display      : System.Address := System.Null_Address;
      Root         : Interfaces.C.unsigned_long := 0;
      Prev_Root_X  : Interfaces.C.int := 0;
      Prev_Root_Y  : Interfaces.C.int := 0;
      Prev_Mask    : Interfaces.C.unsigned := 0;
      Prev_Keymap  : Keymap_Bits := (others => 0);
      Primed       : Boolean := False;
      Is_Available : Boolean := False;
   end record;

   type Optional_Activity_Sample is record
      Has : Boolean := False;
      Val : Activity_Sample;
   end record;

   type Activity_Batch is record
      N      : Natural range 0 .. 3 := 0;
      Item_1 : Activity_Sample;
      Item_2 : Activity_Sample;
      Item_3 : Activity_Sample;
   end record;
end Beep.Linux.Samplers;
