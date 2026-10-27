with Ada.Characters.Handling;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Beep.Audio.Mixer;
with Beep.Audio.Runtime;
with Beep.Audio.Shared;
with Beep.Config;
with Interfaces;
with Interfaces.C;
with Interfaces.C.Strings;
with System;

package body Beep.Audio is
   use Beep.Core.Types;
   use Interfaces;
   use Interfaces.C;
   use type System.Address;

   Snd_Pcm_Stream_Playback      : constant int := 0;
   Snd_Pcm_Access_Rw_Interleaved : constant int := 3;
   Snd_Pcm_Format_S16_Le        : constant int := 2;
   Snd_Pcm_Mode_Non_Blocking    : constant int := 1;
   E_Again                      : constant int := 11;
   Poll_Err                     : constant short := 8;

   subtype Queued_Event is Beep.Audio.Runtime.Queued_Event;

   function snd_pcm_open
     (Pcm    : access System.Address;
      Name   : Interfaces.C.Strings.chars_ptr;
      Stream : int;
      Mode   : int) return int
     with Import, Convention => C, External_Name => "snd_pcm_open";

   function snd_pcm_close (Pcm : System.Address) return int
     with Import, Convention => C, External_Name => "snd_pcm_close";

   function snd_pcm_set_params
     (Pcm            : System.Address;
      Format         : int;
      Access_Mode    : int;
      Channels       : unsigned;
      Rate           : unsigned;
      Soft_Resample  : int;
      Latency_Us     : unsigned) return int
     with Import, Convention => C, External_Name => "snd_pcm_set_params";

   function snd_pcm_prepare (Pcm : System.Address) return int
     with Import, Convention => C, External_Name => "snd_pcm_prepare";

   function snd_pcm_writei
     (Pcm    : System.Address;
      Buffer : System.Address;
      Size   : long) return long
     with Import, Convention => C, External_Name => "snd_pcm_writei";

   function snd_pcm_recover
     (Pcm    : System.Address;
      Err    : int;
      Silent : int) return int
     with Import, Convention => C, External_Name => "snd_pcm_recover";

   function snd_pcm_nonblock (Pcm : System.Address; Non_Blocking : int) return int
     with Import, Convention => C, External_Name => "snd_pcm_nonblock";

   function snd_pcm_poll_descriptors_count (Pcm : System.Address) return int
     with Import, Convention => C,
      External_Name => "snd_pcm_poll_descriptors_count";

   --  Matches C struct pollfd { int fd; short events; short revents; }.
   type Poll_Fd is record
      FD      : int;
      Events  : short;
      Revents : short;
   end record;

   function snd_pcm_poll_descriptors
     (Pcm : System.Address;
      PFds : access Poll_Fd;
      Space : unsigned) return int
     with Import, Convention => C,
      External_Name => "snd_pcm_poll_descriptors";

   function poll (PFds : access Poll_Fd; NFds : unsigned; Timeout_Ms : int) return int
     with Import, Convention => C, External_Name => "poll";

   function Backend_From_Config (Cfg : Beep.Config.App_Config) return Backend_Kind is
      Raw : constant String :=
        Ada.Characters.Handling.To_Lower
          (Ada.Strings.Unbounded.To_String (Cfg.Audio_Backend));
   begin
      if Raw = "null" then
         return Null_Backend;
      elsif Raw = "bell" then
         return Bell_Backend;
      else
         return Alsa_Backend;
      end if;
   end Backend_From_Config;

   procedure Emit_Bell (Gain : Float) is
      use Ada.Text_IO;
   begin
      Put (Character'Val (7));
      if Gain > 0.72 then
         Put (Character'Val (7));
      end if;
      Flush;
   end Emit_Bell;

   Queue : Beep.Audio.Runtime.Event_Queue;
   Mix   : Beep.Audio.Runtime.Mix_Params;
   Ctrl  : Beep.Audio.Runtime.Player_Control;

   G_Backend     : Backend_Kind := Null_Backend;
   G_Alsa_Handle : System.Address := System.Null_Address;
   G_Sample_Rate : unsigned := 44_100;
   G_Active      : Boolean := False;

   M : Beep.Audio.Mixer.Mixer_State;

   --  Write one 512-frame chunk to ALSA as 16-bit signed PCM.
   --  Non-blocking mode with poll-based pacing: the call returns within one
   --  poll timeout (20 ms) even if the device is not ready, so the player
   --  can observe Stop_Requested without a close-from-another-thread race.
   --  Partial writes are looped over the unwritten remainder.
   --  EPIPE and other recoverable errors go through snd_pcm_recover;
   --  an unrecoverable error degrades the session to bell mode.
   procedure Emit_Alsa_Chunk (Handle : System.Address; F32 : Beep.Audio.Mixer.Sample_Buffer) is
      type Int16_Buffer is array (Positive range <>) of aliased Integer_16;
      Buffer  : Int16_Buffer (1 .. F32'Length);
      Written : long := 0;
      Poll_Fds : aliased Poll_Fd;
      Remaining : long;
      N : int;
      R : int;
      Eagain_Retries : Natural := 0;
   begin
      for I in Buffer'Range loop
         Buffer (I) := Shared.To_Int16 (F32 (I));
      end loop;

      loop
         exit when Ctrl.Stop_Requested;

         Remaining := long (Buffer'Length) - Written;
         if Remaining = 0 then
            exit;
         end if;

         N := snd_pcm_writei
           (Handle,
            System.Address (Buffer'Address + Integer (Written) * 2),
            Remaining);
         if N >= 0 then
            Written := Written + N;
            Eagain_Retries := 0;
            exit when Written = long (Buffer'Length);
         end if;

         if N = E_Again then
            --  Device not ready: poll with a 20 ms timeout, then re-loop.
            --  Bounded retries so a stuck device cannot spin the CPU.
            if Eagain_Retries >= 50 then
               --  Drop the chunk; the next chunk will retry.
               return;
            end if;
            Eagain_Retries := Eagain_Retries + 1;
            N := snd_pcm_poll_descriptors_count (Handle);
            if N > 0 then
               N := snd_pcm_poll_descriptors (Handle, Poll_Fds'Access, 1);
               if N > 0 then
                  R := poll (Poll_Fds'Access, 1, 20);
                  if R > 0 then
                     declare
                        Revents : constant short := Poll_Fds.Revents;
                     begin
                        if (Revents and Poll_Err) /= 0 then
                           --  Fatal device error: recover, then retry.
                           if snd_pcm_recover (Handle, -1, 1) < 0 then
                              G_Backend := Bell_Backend;
                              G_Alsa_Handle := System.Null_Address;
                              Ada.Text_IO.Put_Line
                                ("[warn] ALSA device error; falling back to bell");
                              return;
                           end if;
                           Written := 0;
                        end if;
                     end;
                  end if;
               end if;
            end if;
         else
            --  EPIPE or other recoverable error.
            if snd_pcm_recover (Handle, int (N), 1) >= 0 then
               Written := 0;  --  retry the full chunk
            else
               G_Backend := Bell_Backend;
               G_Alsa_Handle := System.Null_Address;
               Ada.Text_IO.Put_Line
                 ("[warn] ALSA unrecoverable; falling back to bell");
               return;
            end if;
         end if;
      end loop;
   end Emit_Alsa_Chunk;

   task type Audio_Player;

   task body Audio_Player is
      Item      : Queued_Event;
      Available : Boolean;
      Params    : Beep.Audio.Mixer.Mix_Parameters;
      F32       : Beep.Audio.Mixer.Sample_Buffer (1 .. 512);
      Bell_Rang : Boolean := False;
   begin
      Ctrl.Mark_Started;
      loop
         Bell_Rang := False;

         --  Drain every queued event this tick (bounded by the queue).
         while G_Active loop
            Queue.Try_Pop (Item, Available);
            exit when not Available;
            if G_Backend = Bell_Backend then
               --  Bell backend: ring per drained event (existing
               --  gain-based double-bell behavior).
               Emit_Bell (Item.Event.Gain);
               Bell_Rang := True;
            else
               Mix.Get
                 (Params.Ambient_Drive,
                  Params.Ambient_Max,
                  Params.Ambient_Decay,
                  Params.Mid_Min,
                  Params.Mid_Max,
                  Params.Fore_Attn);
               Beep.Audio.Mixer.Add_Event (M, Item.Event, Params);
            end if;
         end loop;

         if G_Active and then not Bell_Rang then
            case G_Backend is
               when Null_Backend =>
                  null;  --  events drained and discarded
               when Bell_Backend =>
                  null;  --  already handled in the drain loop
               when Alsa_Backend =>
                  if G_Alsa_Handle /= System.Null_Address then
                     Mix.Get
                       (Params.Ambient_Drive,
                        Params.Ambient_Max,
                        Params.Ambient_Decay,
                        Params.Mid_Min,
                        Params.Mid_Max,
                        Params.Fore_Attn);
                     Beep.Audio.Mixer.Render_Chunk (M, F32, Params);
                     Emit_Alsa_Chunk (G_Alsa_Handle, F32);
                  else
                     --  ALSA handle null: behave like bell backend.
                     G_Backend := Bell_Backend;
                  end if;
            end case;
         end if;

         if Ctrl.Stop_Requested then
            exit;
         end if;

         --  Pacing: ALSA poll provides natural pacing; null/bell need a
         --  short delay to avoid a busy loop.
         if G_Backend = Alsa_Backend and then G_Alsa_Handle /= System.Null_Address then
            null;  --  poll inside Emit_Alsa_Chunk already paced
         else
            delay 0.01;
         end if;
      end loop;
      Ctrl.Mark_Stopped;
   end Audio_Player;

   Player : Audio_Player;

   procedure Initialize (Engine : in out Audio_Engine; Cfg : Beep.Config.App_Config) is
      Requested   : constant Backend_Kind := Backend_From_Config (Cfg);
      Device      : aliased System.Address := System.Null_Address;
      Device_Name : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.Null_Ptr;
      Err         : int;
   begin
      --  Post-shutdown reinitialization is not supported: the player task
      --  is terminal, so we cannot restart playback.
      if Ctrl.Stopped then
         Engine := (others => <>);
         Engine.Backend := Requested;
         Ada.Text_IO.Put_Line
           ("[warn] Initialize after Shutdown is a no-op; playback unavailable");
         return;
      end if;

      Engine := (others => <>);
      Engine.Backend := Requested;
      G_Backend := Requested;
      G_Alsa_Handle := System.Null_Address;
      G_Sample_Rate := Engine.Sample_Rate;
      G_Active := False;
      Beep.Audio.Mixer.Reset (M);
      Mix.Set (Cfg.Audio_Mix);
      Queue.Start;

      if Requested = Null_Backend then
         Engine.Active := True;
         G_Active := True;
         return;
      end if;

      if Requested = Bell_Backend then
         Engine.Active := True;
         G_Active := True;
         return;
      end if;

      Device_Name := Interfaces.C.Strings.New_String ("default");
      Err := snd_pcm_open (Device'Access, Device_Name, Snd_Pcm_Stream_Playback, 0);
      Interfaces.C.Strings.Free (Device_Name);
      if Err < 0 then
         Engine.Backend := Bell_Backend;
         Engine.Active := True;
         G_Backend := Bell_Backend;
         G_Active := True;
         Ada.Text_IO.Put_Line ("[warn] ALSA unavailable; falling back to terminal bell backend");
         return;
      end if;

      Engine.Alsa_Handle := Device;
      Err :=
        snd_pcm_set_params
          (Engine.Alsa_Handle,
           Snd_Pcm_Format_S16_Le,
           Snd_Pcm_Access_Rw_Interleaved,
           1,
           Engine.Sample_Rate,
           1,
           50_000);
      if Err < 0 then
         declare
            Ignore : constant int := snd_pcm_close (Engine.Alsa_Handle);
         begin
            pragma Unreferenced (Ignore);
         end;
         Engine.Alsa_Handle := System.Null_Address;
         Engine.Backend := Bell_Backend;
         Engine.Active := True;
         G_Backend := Bell_Backend;
         G_Alsa_Handle := System.Null_Address;
         G_Active := True;
         Ada.Text_IO.Put_Line ("[warn] ALSA config failed; falling back to terminal bell backend");
         return;
      end if;

      --  Non-blocking mode: writes return EAGAIN instead of blocking,
      --  so the player can observe Stop_Requested within one poll timeout.
      declare
         Nb : constant int := snd_pcm_nonblock (Engine.Alsa_Handle, Snd_Pcm_Mode_Non_Blocking);
      begin
         if Nb < 0 then
            declare
               Ignore : constant int := snd_pcm_close (Engine.Alsa_Handle);
            begin
               pragma Unreferenced (Ignore);
            end;
            Engine.Alsa_Handle := System.Null_Address;
            Engine.Backend := Bell_Backend;
            Engine.Active := True;
            G_Backend := Bell_Backend;
            G_Alsa_Handle := System.Null_Address;
            G_Active := True;
            Ada.Text_IO.Put_Line ("[warn] ALSA non-block failed; falling back to bell");
            return;
         end if;
      end;

      Engine.Active := True;
      G_Backend := Engine.Backend;
      G_Alsa_Handle := Engine.Alsa_Handle;
      G_Active := True;
   end Initialize;

   procedure Reconfigure (Engine : in out Audio_Engine; Cfg : Beep.Config.App_Config) is
   begin
      if not Engine.Active then
         return;
      end if;
      Mix.Set (Cfg.Audio_Mix);
   end Reconfigure;

   procedure Emit
     (Engine : in out Audio_Engine;
      Cfg    : Beep.Config.App_Config;
      Event  : Sound_Event)
   is
      Q : Sound_Event := Event;
   begin
      if not Engine.Active then
         return;
      end if;

      Q.Gain := Shared.Clamp01 (Event.Gain * Cfg.Master_Volume);
      Queue.Push (Q);
   end Emit;

   procedure Shutdown (Engine : in out Audio_Engine) is
      Ignore : int;
   begin
      G_Active := False;
      Queue.Stop;
      Ctrl.Request_Stop;
      Ctrl.Wait_Stopped;

      if Engine.Alsa_Handle /= System.Null_Address then
         Ignore := snd_pcm_close (Engine.Alsa_Handle);
         pragma Unreferenced (Ignore);
      end if;

      G_Backend := Null_Backend;
      G_Alsa_Handle := System.Null_Address;
      Beep.Audio.Mixer.Reset (M);

      Engine := (others => <>);
   end Shutdown;

   function Backend_Name (Engine : Audio_Engine) return String is
   begin
      case Engine.Backend is
         when Null_Backend => return "null";
         when Alsa_Backend => return "alsa";
         when Bell_Backend => return "bell";
      end case;
   end Backend_Name;

   function Is_Active (Engine : Audio_Engine) return Boolean is
   begin
      return Engine.Active;
   end Is_Active;
end Beep.Audio;
