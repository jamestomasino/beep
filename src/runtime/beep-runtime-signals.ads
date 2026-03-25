package Beep.Runtime.Signals is
   --  Install process signal handlers (SIGHUP/SIGINT/SIGTERM).
   procedure Install;
   --  Read and clear pending signal latches.
   --  Reload corresponds to SIGHUP; Stop corresponds to SIGINT/SIGTERM.
   procedure Poll (Reload : out Boolean; Stop : out Boolean);
end Beep.Runtime.Signals;
