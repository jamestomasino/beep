package body Beep.Core.Types is
   function New_State return Engine_State is
   begin
      return (others => <>);
   end New_State;

   function Default_Engine_Config return Engine_Config is
   begin
      return (others => <>);
   end Default_Engine_Config;

   function Motif_Image (Motif : Motif_Type) return String is
   begin
      case Motif is
         when Bip =>
            return "bip";
         when Chirp =>
            return "chirp";
         when Tick =>
            return "tick";
         when Cluster =>
            return "cluster";
         when Run =>
            return "run";
         when Yip =>
            return "yip";
         when Stutter =>
            return "stutter";
         when Bloop =>
            return "bloop";
         when Zap =>
            return "zap";
         when Drone =>
            return "drone";
         when Hum =>
            return "hum";
         when Pad =>
            return "pad";
         when Warble =>
            return "warble";
         when Whirr =>
            return "whirr";
         when Wheee =>
            return "wheee";
         when Wobble =>
            return "wobble";
         when Tsk =>
            return "tsk";
      end case;
   end Motif_Image;
end Beep.Core.Types;
