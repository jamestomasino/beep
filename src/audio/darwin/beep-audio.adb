with Ada.Characters.Handling;
with Ada.Exceptions;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Beep.Audio.Mixer;
with Beep.Audio.Runtime;
with Beep.Audio.Shared;
with Beep.Config;
with Interfaces.C;
with System;

package body Beep.Audio is
   use Beep.Core.Types;
   use Interfaces.C;

   subtype Queued_Event is Beep.Audio.Runtime.Queued_Event;

   function beep_audio_stream_init (Sample_Rate : unsigned) return int
     with Import, Convention => C, External_Name => "beep_audio_stream_init";

   function beep_audio_stream_write
     (Samples : System.Address; Frames : unsigned) return int
     with Import, Convention => C, External_Name => "beep_audio_stream_write";

   procedure beep_audio_stream_shutdown
     with Import, Convention => C, External_Name => "beep_audio_stream_shutdown";

   function Backend_From_Config (Cfg : Beep.Config.App_Config) return Backend_Kind is
      Raw : constant String :=
        Ada.Characters.Handling.To_Lower
          (Ada.Strings.Unbounded.To_String (Cfg.Audio_Backend));
   begin
      if Raw = "null" then
         return Null_Backend;
      elsif Raw = "bell" then
         return Bell_Backend;
      elsif Raw = "coreaudio" or else Raw = "native" or else Raw = "afplay" or else Raw = "miniaudio" then
         return Native_Backend;
      else
         return Bell_Backend;
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
   G_Sample_Rate : unsigned := 44_100;
   G_Active      : Boolean := False;

   M : Beep.Audio.Mixer.Mixer_State;

   --  One player task per process (terminal on stop).  The task drains the
   --  event queue, mixes, and pushes 512-frame chunks to the C bridge, which
   --  blocks on a bounded condvar wait when the ring is full and returns 0 on
   --  shutdown.  Termination is signalled exclusively by Ctrl.Stop_Requested;
   --  the C bridge's own shutdown flag handles the writer path.
   task type Audio_Player;

   task body Audio_Player is
      Item      : Queued_Event;
      Available : Boolean;
      Params    : Beep.Audio.Mixer.Mix_Parameters;
      F32       : Beep.Audio.Mixer.Sample_Buffer (1 .. 512);
   begin
      Ctrl.Mark_Started;
      loop
         --  Drain every queued event this tick.  The queue is bounded, so
         --  this loop terminates.  Shutdown may race here; that is fine,
         --  because the C bridge's shutdown flag (set by Shutdown before
         --  Wait_Stopped) makes any in-flight write return 0 and the loop
         --  exits via Ctrl.Stop_Requested below.
         while G_Active loop
            Queue.Try_Pop (Item, Available);
            exit when not Available;
            if G_Backend = Bell_Backend then
               Emit_Bell (Item.Event.Gain);
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

         --  Render while the mixer has audible state (active voices or a
         --  decaying ambient bed), not only on ticks with new events: voices
         --  and ambient both decay across chunks and must keep advancing.
         --  When idle the chunk is silence, so skipping saves work and keeps
         --  the ring from filling with zero frames.
         if G_Active and then G_Backend /= Bell_Backend and then Beep.Audio.Mixer.Is_Busy (M) then
            Mix.Get
              (Params.Ambient_Drive,
               Params.Ambient_Max,
               Params.Ambient_Decay,
               Params.Mid_Min,
               Params.Mid_Max,
               Params.Fore_Attn);
            Beep.Audio.Mixer.Render_Chunk (M, F32, Params);
            if G_Backend = Native_Backend then
               --  The C bridge blocks on a bounded condvar wait until the
               --  ring has room, so this provides natural pacing when the
               --  consumer is slower than the producer.  A 0 return means
               --  the chunk was dropped under backpressure or the stream
               --  is shutting down; either way the next iteration retries
               --  and a real shutdown is observed via Ctrl.Stop_Requested.
               declare
                  Rc : constant int := beep_audio_stream_write (F32'Address, 512);
               begin
                  pragma Unreferenced (Rc);
               end;
            end if;
         end if;

         if Ctrl.Stop_Requested then
            exit;
         end if;

         --  Pacing: 512 frames at 44.1 kHz is ~11.6 ms of audio.  Delay a
         --  little less than that so the writer stays ahead of the
         --  consumer without busy-spinning.  The C bridge's backpressure
         --  (bounded condvar wait) handles the slow-consumer case.
         delay 0.01;
      end loop;
      Ctrl.Mark_Stopped;
   exception
      when E : others =>
         --  A task that dies without calling Mark_Stopped leaves Shutdown
         --  parked forever in Wait_Stopped.  Always acknowledge termination,
         --  and surface the exception so it is no longer silent.
         Ada.Text_IO.Put_Line
           ("[fatal] audio player task crashed: "
            & Ada.Exceptions.Exception_Information (E));
         Ctrl.Mark_Stopped;
   end Audio_Player;

   Player : Audio_Player;

   procedure Initialize (Engine : in out Audio_Engine; Cfg : Beep.Config.App_Config) is
      Requested : constant Backend_Kind := Backend_From_Config (Cfg);
      Raw       : constant String :=
        Ada.Characters.Handling.To_Lower
          (Ada.Strings.Unbounded.To_String (Cfg.Audio_Backend));
      Rc        : int := 0;
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
      G_Sample_Rate := Engine.Sample_Rate;
      G_Active := True;
      Beep.Audio.Mixer.Reset (M);
      Mix.Set (Cfg.Audio_Mix);
      Queue.Start;

      if Requested = Null_Backend or else Requested = Bell_Backend then
         Engine.Active := True;
         return;
      end if;

      Rc := beep_audio_stream_init (Engine.Sample_Rate);
      if Rc = 0 then
         Engine.Backend := Bell_Backend;
         Engine.Active := True;
         G_Backend := Bell_Backend;
         Ada.Text_IO.Put_Line ("[warn] Darwin audio stream unavailable; falling back to terminal bell backend");
         if Raw /= "bell" then
            Ada.Text_IO.Put_Line ("[warn] requested backend '" & Raw & "' could not be started");
         end if;
         return;
      end if;

      Engine.Active := True;
      G_Backend := Engine.Backend;
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
      Event  : Beep.Core.Types.Sound_Event)
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
   begin
      Queue.Stop;
      Ctrl.Request_Stop;
      --  Signal the C bridge first: a writer blocked in
      --  beep_audio_stream_write wakes, sees the inactive flag, and returns
      --  0 so the player can exit.  This must happen before Wait_Stopped.
      beep_audio_stream_shutdown;
      Ctrl.Wait_Stopped;

      G_Active := False;
      G_Backend := Null_Backend;
      Beep.Audio.Mixer.Reset (M);

      Engine := (others => <>);
   end Shutdown;

   function Backend_Name (Engine : Audio_Engine) return String is
   begin
      case Engine.Backend is
         when Null_Backend => return "null";
         when Native_Backend => return "coreaudio";
         when Bell_Backend => return "bell";
      end case;
   end Backend_Name;

   function Is_Active (Engine : Audio_Engine) return Boolean is
   begin
      return Engine.Active;
   end Is_Active;
end Beep.Audio;
