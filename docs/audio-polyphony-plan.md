# Cross-Platform Polyphonic Audio Plan

## Goal

Replace sequential, full-event audio rendering with a small, robust software mixer that supports overlapping sounds on both Linux and macOS.

The implementation should:

- Keep `Beep.Audio.Emit` asynchronous for callers.
- Support multiple simultaneous sound events.
- Use one output stream per platform.
- Share synthesis and mixing logic across Linux and macOS.
- Avoid new external audio dependencies.
- Keep memory use bounded and avoid allocation in the playback loop.

## Target architecture

```text
Emit(event)
    |
    v
protected event queue
    |
    v
single Audio_Player task
    |-- drain new events into fixed active-voice slots
    |-- render one short mixed chunk
    `-- write chunk through platform adapter
          |-- Linux: ALSA, signed 16-bit
          `-- macOS: AudioQueue, float samples
```

Initial fixed parameters:

- Mono output at 44.1 kHz.
- 512 frames per chunk, or about 11.6 ms.
- At most 16 simultaneous voices.
- Fixed-size arrays only in the mixer.
- Keep the existing 512-event input queue.
- Replace the oldest active voice when all voice slots are occupied.

These parameters should initially remain implementation constants rather than new configuration options. They can be exposed later if real usage demonstrates a need.

## 1. Add a platform-independent mixer

Create `Beep.Audio.Mixer` under `src/audio/`.

The mixer should own:

- A fixed array of active voices.
- Each voice's motif, gain, total duration, current frame, oscillator phases, and timestamp-derived blend.
- Ambient frequency, phase, gain, and decay.

Its primary operations should be:

```ada
procedure Reset;
procedure Add_Event (Event : Sound_Event; Params : Mix_Parameters);
procedure Render_Chunk (Output : out Sample_Buffer; Params : Mix_Parameters);
```

The exact signatures may be adjusted to fit existing package types, but mixer state must remain owned by the audio player task.

`Add_Event` should convert a queued `Sound_Event` into persistent voice state. For ambient motifs, it should also update the mixer-owned ambient state. This allows the current protected `Ambient_Control` to be removed after integration; ambient state will no longer be mutated from multiple tasks.

`Render_Chunk` should:

1. Clear the output buffer.
2. Render the ambient bed once.
3. Add every active voice to the buffer.
4. Advance voice phases and frame positions.
5. Retire completed voices.
6. Apply final output limiting.

This replaces the duplicated full-event renderers:

- Linux `Emit_Alsa` in `src/audio/linux/beep-audio.adb`.
- macOS `Emit_Stream` in `src/audio/darwin/beep-audio.adb`.

Keep reusable calculations such as duration, motif frequency, clamping, and mid-blend selection in `Beep.Audio.Shared`.

## 2. Preserve the asynchronous public API

Keep the public `Beep.Audio.Emit` signature unchanged. It should continue to:

1. Return immediately if the engine is inactive.
2. Apply master-volume scaling.
3. Push the event into the protected event queue.
4. Return without waiting for playback.

Add a nonblocking operation to `Event_Queue`, for example:

```ada
procedure Try_Pop
  (Item      : out Queued_Event;
   Available : out Boolean);
```

The player can use this operation to drain all events available at the start of each chunk without blocking. Keep the existing blocking `Pop` only if it remains useful for the bell backend or startup behavior.

Configuration updates may remain in the existing protected `Mix_Params`. The player should take one parameter snapshot per chunk and use that snapshot consistently for the whole render.

## 3. Convert native playback to a chunk loop

For ALSA and CoreAudio playback, replace the current workflow:

```text
pop one event -> render its entire duration -> write it -> pop next event
```

with:

```text
while running:
    drain pending events into the mixer
    snapshot current mix configuration
    render 512 frames
    write 512 frames
```

The platform write operation should provide playback pacing. A separate manual timing loop should not normally be necessary.

At 512 frames, a newly queued sound should begin within approximately one chunk rather than waiting for earlier sounds to finish.

The null and bell backends do not need sample mixing:

- The null backend should discard queued events cleanly.
- The bell backend can retain a simple event consumer because terminal bells cannot participate in PCM mixing.

## 4. Keep platform adapters thin

### Linux

The shared mixer should produce normalized floating-point samples.

The Linux adapter should:

- Convert one chunk from normalized float samples to signed 16-bit PCM.
- Write the chunk through `snd_pcm_writei`.
- Correctly handle partial writes by continuing with the unwritten portion.
- Continue using `snd_pcm_recover` for underruns and recoverable errors.
- Ensure only the audio player task accesses the ALSA handle.

The ALSA blocking write supplies natural pacing for the chunk loop.

### macOS

The macOS adapter should continue passing float samples to the existing AudioQueue C bridge.

The current ring buffer requires two changes:

1. Reduce excessive buffering so rendered audio cannot accumulate several seconds ahead of playback.
2. Add backpressure instead of silently discarding old samples when the ring is full.

`beep_audio_stream_write` should wait until the ring has room for the submitted chunk. The AudioQueue callback should signal waiting writers after consuming samples. Shutdown must signal the same condition so a blocked writer can exit.

Consider changing the AudioQueue buffers from 2048 frames to 512 frames to align with the mixer chunk size and reduce latency. A small ring holding only a few chunks is sufficient when writes are properly paced.

The C bridge should remain responsible only for AudioQueue lifecycle, buffering, and callbacks. Synthesis and voice mixing should remain in Ada.

## 5. Define bounded overload behavior

Use simple and deterministic policies:

- Support at most 16 active voices.
- When all slots are occupied, replace the oldest active voice.
- Preserve the queue's existing policy of dropping the oldest queued event when its 512 entries are full.
- Sum voices using floating-point arithmetic.
- Reserve modest headroom during summation.
- Apply a soft limiter or final clamp to `[-1.0, 1.0]` before platform conversion.
- Render the ambient bed once per sample, regardless of the number of active voices.

The voice limit prevents unbounded CPU use during event bursts. Draining the input queue into active slots also prevents old sounds from creating a long sequential playback backlog.

## 6. Make shutdown race-free

The backend must not be closed while the player is rendering or writing.

Add a small protected player-control object with operations equivalent to:

```ada
procedure Request_Stop;
function Stop_Requested return Boolean;
procedure Mark_Stopped;
entry Wait_Stopped;
```

Use this shutdown order:

1. Stop accepting new events.
2. Request player termination.
3. Wake any blocked platform write.
4. Let the player finish or abort its current short chunk.
5. Wait for the player to acknowledge termination.
6. Close ALSA or AudioQueue resources.
7. Reset mixer and engine state.

Shutdown must remain safe to call repeatedly.

The design should also document whether reinitialization after shutdown is supported. If the global Ada task remains terminal after shutdown, `Initialize` should not imply that playback can be restarted in the same process.

## 7. Add hardware-independent mixer tests

Add `src/tests/beep_audio_tests.adb`, register it in `beep.gpr`, and run it from the Makefile's `test` target.

The tests must exercise the shared mixer without opening an audio device.

Cover at least:

- Two simultaneous voices contribute to the same chunk.
- A second event starts before the first event ends.
- Voices expire at the expected frame.
- An empty mixer renders silence.
- Output stays within the permitted range under maximum polyphony.
- The ambient bed is added once rather than once per active voice.
- Voice stealing is deterministic.
- Identical event sequences produce identical samples.
- `Reset` clears all voices and ambient state.
- Chunk boundaries do not introduce oscillator discontinuities within a voice.

Platform validation should additionally confirm:

- Linux handles partial writes and ALSA recovery.
- macOS applies backpressure without dropping queued PCM.
- Shutdown does not deadlock when a write is blocked.

## Delivery sequence

### Phase 1: Shared mixer

- Add the fixed voice representation.
- Add event-to-voice initialization.
- Add chunk rendering and limiting.
- Add hardware-independent unit tests.

### Phase 2: Linux integration

- Replace full-event rendering with the chunk loop.
- Add float-to-16-bit conversion.
- Handle partial ALSA writes.
- Verify overlapping playback on a real device.

### Phase 3: macOS integration

- Use the same shared chunk mixer.
- Align AudioQueue and mixer chunk sizes.
- Add bounded buffering and writer backpressure.
- Verify overlapping playback on a real device.

### Phase 4: Lifecycle hardening

- Add coordinated stop and acknowledgment.
- Test blocked-write shutdown behavior.
- Confirm repeated shutdown is harmless.

### Phase 5: Cleanup

- Remove the duplicated Linux and macOS full-event synthesis functions.
- Remove `Ambient_Control` if ambient state is fully mixer-owned.
- Update audio architecture comments and user-facing documentation.

## Acceptance criteria

The work is complete when:

- Two events emitted less than one event-duration apart audibly overlap on Linux and macOS.
- `Emit` remains nonblocking apart from its short protected queue operation.
- Both platforms use the same Ada synthesis and mixing implementation.
- Only sample-format conversion and device I/O remain platform-specific.
- Playback latency remains bounded to approximately one render chunk plus device buffering.
- Event bursts cannot cause unbounded allocation, CPU use, or playback backlog.
- macOS no longer drops old PCM data when its ring is full.
- ALSA partial writes are handled correctly.
- Shutdown cannot close an audio device while the player is using it.
- Mixer behavior is covered by deterministic tests that require no audio hardware.
- Both platform configurations build successfully:

```sh
BEEP_OS=linux alr build
BEEP_OS=darwin alr build
make test
```

## Non-goals

To keep the project small, this change should not introduce:

- Multiple device streams.
- One playback task per voice.
- A third-party audio or DSP library.
- Dynamic voice allocation.
- Stereo spatialization.
- Runtime-configurable chunk size or polyphony until there is a demonstrated need.
- A general-purpose effects or plugin system.

