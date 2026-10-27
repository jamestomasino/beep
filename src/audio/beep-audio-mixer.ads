with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;
with Beep.Audio.Shared;
with Beep.Core.Types;

package Beep.Audio.Mixer is
   --  Plain (non-protected) software mixer with fixed voice slots.
   --  A single Audio_Player task owns one Mixer_State at runtime;
   --  tests construct their own state values without tasks or devices.

   --  Number of simultaneous voices supported.
   Max_Voices : constant Positive := 16;

   --  Per-voice state.
   type Voice is record
      Active      : Boolean := False;
      Sequence    : Natural := 0;   -- insertion order, for deterministic stealing
      Frequency   : Float := 0.0;   -- foreground frequency (Hz)
      Mid_Frequency : Float := 0.0; -- mid frequency (Hz)
      Gain        : Float := 0.0;
      Total_Frames : Positive := 1;
      Frame       : Natural := 0;  -- current frame within the voice
      Fore_Phase  : Float := 0.0;  -- persistent phase accumulator (radians)
      Mid_Phase   : Float := 0.0;
      Mid_Blend   : Float := 0.0;  -- 0..1, fraction routed to mid
      Fore_Attn   : Float := 0.0;  -- foreground attenuation from mid blend
   end record;

   type Voice_Array is array (Positive range 1 .. Max_Voices) of Voice;

   --  Ambient bed state (owned by the mixer, mutated only by the player task).
   type Ambient_State is record
      Target_Freq  : Float := 92.0;
      Current_Freq : Float := 92.0;
      Level        : Float := 0.0;
      Phase        : Float := 0.0;
   end record;

   --  Mix parameters snapshot, taken once per chunk from Mix_Params.
   type Mix_Parameters is record
      Ambient_Drive : Float := 0.32;
      Ambient_Max   : Float := 0.30;
      Ambient_Decay : Float := 0.992;
      Mid_Min       : Float := 0.16;
      Mid_Max       : Float := 0.52;
      Fore_Attn     : Float := 0.55;
   end record;

   --  Full mixer state.
   type Mixer_State is record
      Voices   : Voice_Array := (others => (others => <>));
      Ambient  : Ambient_State := (others => <>);
      Sequence : Natural := 0;
   end record;

   --  Sample buffer for one chunk (512 frames at 44.1 kHz).
   type Sample_Buffer is array (Positive range <>) of Float;

   --  Reset all voices, ambient state, and the sequence counter.
   procedure Reset (M : in out Mixer_State);

   --  Convert a queued Sound_Event into a persistent voice.
   --  For ambient motifs, also updates the ambient bed state.
   --  When all voice slots are occupied, replaces the oldest (lowest sequence).
   procedure Add_Event
     (M      : in out Mixer_State;
      Event  : Beep.Core.Types.Sound_Event;
      Params : Mix_Parameters);

   --  Render one chunk of 512 frames into Output.
   --  Steps: clear, ambient bed, active voices, advance phases, retire, limit.
   procedure Render_Chunk
     (M      : in out Mixer_State;
      Output : out Sample_Buffer;
      Params : Mix_Parameters);

   --  Number of currently active voices.
   function Active_Voice_Count (M : Mixer_State) return Natural;
end Beep.Audio.Mixer;
