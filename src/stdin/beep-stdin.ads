with Ada.Strings.Unbounded;
with Interfaces.C;

--  Beep.Stdin
--  =========
--  A small, non-blocking line reader over standard input.
--
--  beep is a continuous sonifier, so it must read stdin cooperatively rather
--  than with a blocking Get_Line: each tick it waits up to ~40 ms for a full
--  line and reports what (if anything) it got. This package owns the poll/read
--  interop and the reassembly of lines that arrive split across reads.
--
--  The C functions are imported directly (they are POSIX and available on both
--  darwin and linux), matching the way the audio layer binds into libaudio.
package Beep.Stdin is

   --  A line reader over a file descriptor (stdin by default).
   type Line_Reader is tagged private;

   --  Bind the reader to Fd. Default is standard input (fd 0). Read_Chunk is
   --  how many bytes to pull per read; the default is large enough for long log
   --  lines (tests may lower it to exercise split-line reassembly).
   procedure Initialize (R          : in out Line_Reader;
                         Fd         : Interfaces.C.int := 0;
                         Read_Chunk : Natural          := 65_536);

   --  Wait up to Timeout_Ms for one complete line on the reader's descriptor.
   --    Eof       => input has closed; the reader is finished (call again only
   --                 to observe Eof; it stays true).
   --    Have_Line => Line holds one complete line, newline stripped.
   --    else      => no line yet this tick; call again later.
   --  A trailing line without a final newline is delivered on EOF.
   procedure Poll (R          : in out Line_Reader;
                   Line       : out Ada.Strings.Unbounded.Unbounded_String;
                   Have_Line  : out Boolean;
                   Eof        : out Boolean;
                   Timeout_Ms : Natural);

   --  True when standard input is an interactive terminal (a warning case for beep).
   function Is_TTY return Boolean;

private
   --  C interop (POSIX; identical on darwin and linux). Kept private: callers
   --  only ever use Initialize / Poll / Is_TTY.

   --  A poll(2) descriptor. Field widths match `struct pollfd` exactly
   --  (int, short, short) so the struct layout is ABI-correct.
   type Pollfd is record
      Fd     : Interfaces.C.int;
      Events : Interfaces.C.short;
      Rev    : Interfaces.C.short;
   end record;

   --  int poll(struct pollfd *fds, nfds_t nfds, int timeout);
   --  Named Poll_2 to avoid colliding with the public Poll procedure.
   function Poll_2 (Fds        : access Pollfd;
                    Nfds       : Interfaces.C.unsigned_long;
                    Timeout_Ms : Interfaces.C.int) return Interfaces.C.int
      with Import, Convention => C, External_Name => "poll";

   --  ssize_t read(int fd, void *buf, size_t count);
   function Read_Bytes (Fd    : Interfaces.C.int;
                        Buf   : access Character;
                        Count : Interfaces.C.size_t) return Interfaces.C.long
      with Import, Convention => C, External_Name => "read";

   --  int isatty(int fd);
   function Is_Tty (Fd : Interfaces.C.int) return Interfaces.C.int
      with Import, Convention => C, External_Name => "isatty";

   type Line_Reader is tagged record
      Fd       : Interfaces.C.int := 0;
      Read_Chunk : Natural       := 65_536;
      Buf  : Ada.Strings.Unbounded.Unbounded_String := Ada.Strings.Unbounded.Null_Unbounded_String;
      Done : Boolean := False;
   end record;
end Beep.Stdin;
