with Ada.Directories;
with Ada.Strings.Unbounded;
with Beep.Linux.Samplers;

package body Beep.Platform.Samplers.Linux is
   function Available return Boolean is
   begin
      return Ada.Directories.Exists ("/proc") and then not Ada.Directories.Exists ("/System/Library/Sounds");
   end Available;

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
   end Initialize;

   procedure Shutdown (Sampler : in out X11_Sampler) is
   begin
      Beep.Linux.Samplers.Shutdown (Sampler.Linux);
   end Shutdown;

   function Poll_Cpu
     (Sampler   : in out Cpu_Sampler;
      Cfg       : Beep.Core.Types.Engine_Config;
      Debug     : Boolean;
      Timestamp : Beep.Core.Types.Milliseconds) return Optional_Activity_Sample
   is
      S : constant Beep.Linux.Samplers.Optional_Activity_Sample :=
        Beep.Linux.Samplers.Poll_Cpu (Sampler.Linux, Cfg, Debug, Timestamp);
   begin
      if Beep.Linux.Samplers.Has_Value (S) then
         return (Has => True, Val => Beep.Linux.Samplers.Value (S));
      end if;
      return (Has => False, Val => Empty_Sample);
   end Poll_Cpu;

   function Poll_System
     (Sampler   : in out System_Sampler;
      Timestamp : Beep.Core.Types.Milliseconds) return Activity_Batch
   is
      LB : constant Beep.Linux.Samplers.Activity_Batch := Beep.Linux.Samplers.Poll_System (Sampler.Linux, Timestamp);
      Batch : Activity_Batch :=
        (N => 0,
         Item_1 => Empty_Sample,
         Item_2 => Empty_Sample,
         Item_3 => Empty_Sample,
         Item_4 => Empty_Sample,
         Item_5 => Empty_Sample,
         Item_6 => Empty_Sample);
   begin
      for I in 1 .. Beep.Linux.Samplers.Count (LB) loop
         Add_Sample (Batch, Beep.Linux.Samplers.Item (LB, I));
      end loop;
      return Batch;
   end Poll_System;

   function Poll_Net
     (Sampler   : in out Net_Sampler;
      Timestamp : Beep.Core.Types.Milliseconds) return Optional_Activity_Sample
   is
      S : constant Beep.Linux.Samplers.Optional_Activity_Sample :=
        Beep.Linux.Samplers.Poll_Net (Sampler.Linux, Timestamp);
   begin
      if Beep.Linux.Samplers.Has_Value (S) then
         return (Has => True, Val => Beep.Linux.Samplers.Value (S));
      end if;
      return (Has => False, Val => Empty_Sample);
   end Poll_Net;

   function Poll_X11
     (Sampler   : in out X11_Sampler;
      Timestamp : Beep.Core.Types.Milliseconds) return Activity_Batch
   is
      LB : constant Beep.Linux.Samplers.Activity_Batch := Beep.Linux.Samplers.Poll_X11 (Sampler.Linux, Timestamp);
      Batch : Activity_Batch :=
        (N => 0,
         Item_1 => Empty_Sample,
         Item_2 => Empty_Sample,
         Item_3 => Empty_Sample,
         Item_4 => Empty_Sample,
         Item_5 => Empty_Sample,
         Item_6 => Empty_Sample);
   begin
      for I in 1 .. Beep.Linux.Samplers.Count (LB) loop
         Add_Sample (Batch, Beep.Linux.Samplers.Item (LB, I));
      end loop;
      return Batch;
   end Poll_X11;

   function X11_Active (Sampler : X11_Sampler) return Boolean is
   begin
      return Beep.Linux.Samplers.X11_Active (Sampler.Linux);
   end X11_Active;
end Beep.Platform.Samplers.Linux;
