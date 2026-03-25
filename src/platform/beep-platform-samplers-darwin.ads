with Beep.Core.Types;

private package Beep.Platform.Samplers.Darwin is
   function Available return Boolean;

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
end Beep.Platform.Samplers.Darwin;
