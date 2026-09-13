with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Interfaces.C;

package body Beep.Stdin is

   use Interfaces.C;

   --  POLLIN: readable data available (1 on POSIX).
   Pollin : constant short := 1;

   function Is_TTY return Boolean is
   begin
      return Is_Tty (0) /= 0;
   end Is_TTY;

   procedure Initialize (R          : in out Line_Reader;
                         Fd         : Interfaces.C.int := 0;
                         Read_Chunk : Natural          := 65_536) is
   begin
      R.Fd         := Fd;
      R.Read_Chunk := Read_Chunk;
      R.Buf        := Ada.Strings.Unbounded.Null_Unbounded_String;
      R.Done       := False;
   end Initialize;

   --  Pop one complete line (newline stripped) from R.Buf. Returns False when
   --  no complete line is buffered yet.
   function Take_Line (R    : in out Line_Reader;
                       Line : out Ada.Strings.Unbounded.Unbounded_String) return Boolean
   is
      S      : constant String := Ada.Strings.Unbounded.To_String (R.Buf);
      Nl     : Natural;
      LF_Str : constant String := (1 => Character'Val (10));
   begin
      Nl := Ada.Strings.Fixed.Index (S, LF_Str);
      if Nl = 0 then
         return False;
      end if;

      if Nl > S'First then
         Line := Ada.Strings.Unbounded.To_Unbounded_String (S (S'First .. Nl - 1));
      else
         Line := Ada.Strings.Unbounded.Null_Unbounded_String;
      end if;

      --  Keep the remainder (possibly the start of the next line) for later.
      if Nl < S'Last then
         R.Buf := Ada.Strings.Unbounded.To_Unbounded_String (S (Nl + 1 .. S'Last));
      else
         R.Buf := Ada.Strings.Unbounded.Null_Unbounded_String;
      end if;

      return True;
   end Take_Line;

   procedure Poll (R          : in out Line_Reader;
                   Line       : out Ada.Strings.Unbounded.Unbounded_String;
                   Have_Line  : out Boolean;
                   Eof        : out Boolean;
                   Timeout_Ms : Natural)
   is
      Fd    : constant int := R.Fd;
      Fds   : aliased Pollfd := (Fd => Fd, Events => Pollin, Rev => 0);
      N     : int;
      Got   : long;
      type Chunk_Type is array (1 .. 65_536) of aliased Character;
      Chunk : Chunk_Type;
   begin
      Have_Line := False;
      Eof       := False;

      if R.Done then
         Eof := True;
         return;
      end if;

      --  Wait up to Timeout_Ms for data to become available.
      N := Poll_2 (Fds'Access, 1, int (Timeout_Ms));

      if N < 0 then
         --  Poll failed (e.g. interrupted); treat as "nothing this tick".
         return;
      end if;

      if N = 0 then
         --  No data yet this tick.
         return;
      end if;

      --  Read whatever is available into the chunk buffer.
      Got := Read_Bytes (Fd, Chunk (1)'Access, size_t (R.Read_Chunk));

      if Got < 0 then
         --  Read error: stop polling the fd.
         R.Done := True;
         Eof    := True;
         return;
      end if;

      if Got = 0 then
         --  EOF: upstream closed. Flush any trailing partial line so the last
         --  line of a piped log is not lost, then report EOF.
         R.Done := True;
         Eof    := True;
         if Take_Line (R, Line) then
            Have_Line := True;
         else
            if Ada.Strings.Unbounded.Length (R.Buf) > 0 then
               Line      := R.Buf;
               R.Buf     := Ada.Strings.Unbounded.Null_Unbounded_String;
               Have_Line := True;
            end if;
         end if;
         return;
      end if;

      --  Append the freshly read bytes to the line buffer.
      for I in 1 .. Natural (Got) loop
         Ada.Strings.Unbounded.Append (R.Buf, Chunk (I));
      end loop;

      Have_Line := Take_Line (R, Line);
   end Poll;
end Beep.Stdin;
