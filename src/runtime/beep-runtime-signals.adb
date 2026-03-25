with Interfaces.C;

package body Beep.Runtime.Signals is
   use Interfaces.C;

   Sighup  : constant int := 1;
   Sigint  : constant int := 2;
   Sigterm : constant int := 15;

   Reload_Pending : int := 0;
   pragma Atomic (Reload_Pending);
   Stop_Pending : int := 0;
   pragma Atomic (Stop_Pending);

   type Signal_Handler is access procedure (Sig : int) with Convention => C;

   function C_Signal (Sig : int; Handler : Signal_Handler) return Signal_Handler
     with Import, Convention => C, External_Name => "signal";

   procedure Raw_Handler (Sig : int) with Convention => C;

   procedure Raw_Handler (Sig : int) is
   begin
      if Sig = Sighup then
         Reload_Pending := 1;
      elsif Sig = Sigint or else Sig = Sigterm then
         Stop_Pending := 1;
      end if;
   end Raw_Handler;

   procedure Install is
      Ignore : Signal_Handler;
   begin
      Ignore := C_Signal (Sighup, Raw_Handler'Access);
      Ignore := C_Signal (Sigint, Raw_Handler'Access);
      Ignore := C_Signal (Sigterm, Raw_Handler'Access);
      pragma Unreferenced (Ignore);
   exception
      when others =>
         null;
   end Install;

   procedure Poll (Reload : out Boolean; Stop : out Boolean) is
   begin
      Reload := Reload_Pending /= 0;
      Stop := Stop_Pending /= 0;
      Reload_Pending := 0;
   end Poll;
end Beep.Runtime.Signals;
