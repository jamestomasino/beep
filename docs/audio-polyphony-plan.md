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
- Make shutdown race-free: no thread may close a device while the player is using it.

## Target architecture

```text
Emit(event)
    |
    v
protected event queue (Try_Pop only)
    |
    v
single Audio_Player task
    |-- drain new events into fixed active-voice slots
    |-- render one short mixed chunk
    `-- write chunk through platform adapter
          |-- Linux: ALSA (non-blocking + poll), signed 16-bit
          `-- macOS: AudioQueue (backpressured ring), float samples
```

Initial fixed parameters:

- Mono output at 44.1 kHz.
- 512 frames per chunk, or about 11.6 ms.
- At most 16 simultaneous voices.
- Fixed-size arrays only in the mixer.
- Keep the existing 512-event input queue with drop-oldest when full.
- Replace the oldest active voice when all voice slots are occupied
  (deterministic: the voice with the lowest insertion sequence number).

These parameters should initially remain implementation constants rather than new
configuration options. They can be exposed later if real usage demonstrates a need.

## 1. Add a platform-independent mixer

Create `Beep.Audio.Mixer` under `src/audio/`.

**Ownership and testability:** `Beep.Audio.Mixer` is a *plain* package, not a
protected type. It exposes a record type `Mixer_State` plus procedures that take
`in out Mixer_State`:

```ada
type Mixer_State is record ... end record;

procedure Reset (M : in out Mixer_State);
procedure Add_Event (M : in out Mixer_State; Event : Sound_Event; Params : Mix_Parameters);
procedure Render_Chunk (M : in out Mixer_State; Output : out Sample_Buffer; Params : Mix_Parameters);
```

The `Audio_Player` task owns a single `Mixer_State` instance; no other task ever
touches it. Tests construct their own `Mixer_State` values and drive the same
procedures directly, with no audio device and no tasks. This keeps the mixer
deterministic and unit-testable while preserving single-task ownership at runtime.

The mixer should own:

- A fixed array of active voices (16 slots).
- Each voice's motif, gain, total duration, current frame, oscillator phases
  (foreground and mid), and timestamp-derived blend.
- A monotonically increasing voice sequence counter for deterministic stealing.
- Ambient frequency (target and current), phase, gain, and decay.

`Add_Event` should convert a queued `Sound_Event` into persistent voice state.
For ambient motifs, it should also update the mixer-owned ambient state. This
allows the current protected `Ambient_Control` to be removed after integration;
ambient state will no longer be mutated from multiple tasks.

`Render_Chunk` should:

1. Clear the output buffer.
2. Render the ambient bed once for the chunk.
3. Add every active voice to the buffer.
4. Advance voice phases and frame positions.
5. Retire completed voices.
6. Apply final output limiting (soft-limit or clamp to `[-1.0, 1.0]`).

Oscillator phase is a persistent accumulator per voice (not recomputed from
absolute time), which makes chunk boundaries continuous by construction.

Ambient decay becomes time-based: the decay factor is applied per sample
(normalized from the existing per-call rate) rather than per `Snapshot` call,
so decay speed no longer depends on how often the player loop happens to run.

This replaces the duplicated full-event renderers:

- Linux `Emit_Alsa` in `src/audio/linux/beep-audio.adb`.
- macOS `Emit_Stream` in `src/audio/darwin/beep-audio.adb`.

Keep reusable calculations such as duration, motif frequency, clamping, and
mid-blend selection in `Beep.Audio.Shared`. Add one pure helper there for
sample conversion:

```ada
function To_Int16 (Sample : Float) return Integer_16;
```

which clamps to `[-1.0, 1.0]` and rounds (`Float'Round (S * 32_767.0)`) instead
of the current truncating `Integer (S * 32_767.0)`. The Linux adapter is the only
caller; the macOS path stays float.

## 2. Preserve the asynchronous public API

Keep the public `Beep.Audio.Emit` signature unchanged. It should continue to:

1. Return immediately if the engine is inactive.
2. Apply master-volume scaling.
3. Push the event into the protected event queue.
4. Return without waiting for playback.

**Configuration snapshot policy:** `Mix_Params.Set` moves out of `Emit` and is
called only from `Initialize` and `Reconfigure`. `Emit` no longer touches
`Mix_Params` or `Ambient_Control` at all; ambient drive is applied by the mixer
inside the player task. `Emit`'s only shared-state operation is the queue push.

**Queue consumption:** add a nonblocking operation to `Event_Queue`:

```ada
procedure Try_Pop
  (Item      : out Queued_Event;
   Available : out Boolean);
```

All player backends use `Try_Pop` in a loop. The existing blocking `Pop` entry
is removed: with `Try_Pop`, the player is never blocked in the queue, which
simplifies shutdown (no wakeup of a blocked `Pop` is needed) and makes the
null/bell loops trivial. The queue keeps its drop-oldest policy when full.

The player takes one `Mix_Params` snapshot per loop iteration and uses that
snapshot consistently for `Add_Event` and `Render_Chunk`.

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

The platform write operation should provide playback pacing (see section 4).
A separate manual timing loop should not normally be necessary.

At 512 frames, a newly queued sound should begin within approximately one chunk
rather than waiting for earlier sounds to finish.

### Backend-specific player loops

The single `Audio_Player` task serves all backends. Per-backend behavior:

- **ALSA (Linux, handle open):** the chunk loop above.
- **CoreAudio (macOS, stream active):** the chunk loop above.
- **Null:** drain and discard events with a short delay (`Try_Pop` + `delay 0.01`)
  until stop is requested, then exit.
- **Bell:** drain events and ring the terminal bell (existing gain-based
  double-bell behavior) with a short delay, until stop is requested, then exit.
- **ALSA/CoreAudio fallback to bell** (device open failed at `Initialize`, or the
  device handle is null at runtime): behave exactly like the bell backend.
  This preserves the current fallback path where `G_Backend` is
  `Alsa_Backend` but `Alsa_Handle` is null.

A fatal, unrecoverable device error mid-playback (ALSA recover failed, or the
C bridge reports inactive) degrades the session to bell mode rather than
terminating the player, matching current fallback semantics.

The 50 ms delay branch that currently emits ambient bursts is removed entirely;
ambient is rendered inside every chunk by the shared mixer.

## 4. Keep platform adapters thin

### Linux

The shared mixer should produce normalized floating-point samples.

The Linux adapter should:

- Convert one chunk from normalized float samples to signed 16-bit PCM using
  `Beep.Audio.Shared.To_Int16` (clamp + round).
- Write the chunk through `snd_pcm_writei`.
- **Use non-blocking mode** (`Snd_Pcm_Mode_Non_Blocking`) with `poll` on the
  PCM file descriptor (`snd_pcm_poll_descriptors` or `snd_pcm_nonblock` + the
  descriptor from `snd_pcm_info`) and a timeout of 10-20 ms. This gives:
  - natural pacing (poll returns when the device can accept data),
  - a bounded loop where the player can check `Stop_Requested` every poll
    timeout, so shutdown never needs to close the handle from another thread,
  - clean `EAGAIN` handling.
- Handle partial writes: loop `snd_pcm_writei` over the unwritten remainder of
  the chunk until fully written or a fatal error.
- Continue using `snd_pcm_recover` for `EPIPE` and other recoverable errors;
  on `EAGAIN`, simply re-poll.
- Only the audio player task touches the ALSA handle.

**Shutdown wake mechanism (defined):** the player exits because its poll loop
observes `Stop_Requested` within one poll timeout; `Shutdown` does *not* close
the handle to unblock a write. `snd_pcm_close` is called only after
`Wait_Stopped` (section 6). This removes the close-during-write race.

### macOS

The macOS adapter should continue passing float samples to the existing AudioQueue
C bridge. The C bridge keeps its three exported symbols
(`beep_audio_stream_init`, `beep_audio_stream_write`,
`beep_audio_stream_shutdown`); no new symbols are required. Behavior changes:

1. **Reduce excessive buffering:** the ring is currently 262144 frames
   (~5.9 s). Reduce it to a few chunks (e.g. 8 x 512 = 4096 frames).
2. **Add backpressure:** `beep_audio_stream_write` must block on a
   `pthread_cond` (guarded by the existing `g_lock`) until the ring has room
   for the submitted chunk, instead of silently dropping old samples.
3. **Shutdown signals the wait:** `beep_audio_stream_shutdown` sets the
   inactive flag, broadcasts the condition variable under `g_lock`, then
   disposes the queue and resets the ring. A writer blocked in `write` wakes,
   sees the inactive flag, and returns an error code (0) so the Ada player can
   exit. The writer must also re-check the flag in its wait loop (spurious
   wakeup safety).
4. **Align AudioQueue buffers:** change `BEEP_STREAM_BUFFER_FRAMES` from 2048
   to 512 to match the mixer chunk size and reduce latency.

The C bridge remains responsible only for AudioQueue lifecycle, buffering, and
callbacks. Synthesis and voice mixing remain in Ada.

## 5. Define bounded overload behavior

Use simple and deterministic policies:

- Support at most 16 active voices.
- When all slots are occupied, replace the oldest active voice (lowest
  insertion sequence number).
- Preserve the queue's existing policy of dropping the oldest queued event when
  its 512 entries are full.
- Sum voices using floating-point arithmetic.
- Reserve modest headroom during summation (e.g. divide the per-voice sum by a
  small constant or scale gains) so 16 simultaneous voices at full gain do not
  saturate trivially.
- Apply a soft limiter or final clamp to `[-1.0, 1.0]` before platform conversion.
- Render the ambient bed once per chunk, regardless of the number of active voices.

The voice limit prevents unbounded CPU use during event bursts. Draining the
input queue into active slots also prevents old sounds from creating a long
sequential playback backlog.

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

1. Stop accepting new events (`Event_Queue.Stop`).
2. `Request_Stop` on the player control.
3. Platform-specific unblock, only where needed:
   - Linux: none required; the poll loop observes `Stop_Requested` within one
     poll timeout (10-20 ms).
   - macOS: `beep_audio_stream_shutdown` signals the writer condition; the
     blocked `write` returns.
4. Let the player finish or abort its current short chunk.
5. `Wait_Stopped` for the player to acknowledge termination (`Mark_Stopped`).
6. Close ALSA or AudioQueue resources (Linux: `snd_pcm_close` here, after the
   player has exited).
7. Reset mixer and engine state.

Shutdown must remain safe to call repeatedly: `Wait_Stopped` must not deadlock
if the player has already exited (guard with the `Mark_Stopped` flag / a
"player ever started" check).

**Reinitialization policy (decided):** reinitialization after shutdown is
*not supported* in the same process. The global `Audio_Player` task is terminal
after it exits, so `Initialize` after `Shutdown` cannot restart playback.
Document this in the spec comment on `Initialize`, and make a post-shutdown
`Initialize` a no-op that leaves `Engine.Active = False` and logs a warning,
rather than silently claiming success.

## 7. Add hardware-independent mixer tests

Add `src/tests/beep_audio_tests.adb`, register it in `beep.gpr`
(`for Main use` + `Builder.Executable`), and run it from the Makefile's `test`
target.

The tests must exercise the shared mixer without opening an audio device and
without tasks (plain `Mixer_State` values).

Cover at least:

- Two simultaneous voices contribute to the same chunk.
- A second event starts before the first event ends.
- Voices expire at the expected frame.
- An empty mixer renders silence.
- Output stays within the permitted range under maximum polyphony (16 voices,
  full gain).
- The ambient bed is added once rather than once per active voice.
- Voice stealing is deterministic (oldest voice replaced, same input => same
  result).
- Identical event sequences produce identical samples.
- `Reset` clears all voices, the sequence counter, and ambient state.
- Chunk boundaries do not introduce oscillator discontinuities within a voice
  (phase accumulator continuity across `Render_Chunk` calls).
- `To_Int16` clamps and rounds correctly (boundary values, saturation).
- Ambient decay is time-based: N rendered frames decay by the same factor
  regardless of chunking.

Platform validation should additionally confirm:

- Linux: partial writes and `EPIPE` recovery; the poll loop exits within one
  poll timeout after `Request_Stop` with no close-from-another-thread.
- macOS: `beep_audio_stream_write` blocks when the ring is full and returns
  promptly after shutdown signals; no queued PCM is dropped under normal
  backpressure.
- Shutdown does not deadlock when a write is blocked, and repeated shutdown is
  a no-op.

## Behavior change notes

Call these out in the PR description and user-facing docs so they are not read
as regressions:

- The ambient bed changes from 44 ms bursts emitted every ~50 ms (with a
  per-event phase-continuity bug: phase advanced per sample *per event*) to a
  continuous bed rendered inside every chunk with a persistent phase
  accumulator. Audibly smoother; decay rate is now time-based rather than
  call-based, so the perceived decay speed changes slightly.
- Sounds now overlap instead of playing sequentially; a burst of events is
  mixed rather than queued for sequential playback.
- 16-bit output rounds instead of truncating (negligible, but deterministic).
- macOS latency drops (ring and AudioQueue buffers shrink) and the old
  drop-oldest-PCM behavior is replaced by backpressure.
- Reinitialization after shutdown is explicitly unsupported (documented).

## Delivery sequence

### Phase 1: Shared mixer

- Add `Beep.Audio.Mixer` (plain package, `Mixer_State`) with the fixed voice
  representation, event-to-voice initialization, ambient state, chunk
  rendering, and limiting.
- Add `Beep.Audio.Shared.To_Int16`.
- Add hardware-independent unit tests (`beep_audio_tests`) and register them
  in `beep.gpr` and the Makefile.

### Phase 2: Linux integration

- Convert ALSA to non-blocking mode with `poll`-based pacing.
- Replace full-event rendering with the chunk loop; add float-to-16-bit
  conversion via `To_Int16`.
- Handle partial writes and `EPIPE`/`EAGAIN` paths.
- Wire the null/bell/fallback player loops.
- Verify overlapping playback on a real device.

### Phase 3: macOS integration

- Use the same shared chunk mixer.
- Update the C bridge: smaller ring, condition-variable backpressure in
  `beep_audio_stream_write`, shutdown signaling, 512-frame AudioQueue buffers.
- Wire the player loop and bell fallback.
- Verify overlapping playback on a real device.

### Phase 4: Lifecycle hardening

- Add the protected player-control object and the shutdown order from section 6.
- Implement the post-shutdown `Initialize` no-op policy.
- Test blocked-write shutdown behavior and repeated shutdown.

### Phase 5: Cleanup

- Remove the duplicated Linux and macOS full-event synthesis functions
  (`Emit_Alsa`, `Emit_Stream`, `Emit_Ambient_Chunk` on both platforms).
- Remove `Ambient_Control`, the `G_Ambient_Phase` globals, and the 50 ms
  delay branch.
- Remove `Mix_Params.Set` from `Emit`; remove the blocking `Pop` entry.
- Update audio architecture comments and user-facing documentation, including
  the reinitialization policy and behavior change notes.

## Acceptance criteria

The work is complete when:

- Two events emitted less than one event-duration apart audibly overlap on
  Linux and macOS.
- `Emit` remains nonblocking apart from its short protected queue operation and
  no longer touches `Mix_Params` or ambient state.
- Both platforms use the same Ada synthesis and mixing implementation.
- Only sample-format conversion and device I/O remain platform-specific.
- Playback latency remains bounded to approximately one render chunk plus
  device buffering.
- Event bursts cannot cause unbounded allocation, CPU use, or playback backlog.
- macOS no longer drops old PCM data when its ring is full; a blocked writer
  wakes promptly on shutdown.
- ALSA runs in non-blocking mode with poll-based pacing; partial writes and
  `EPIPE` are handled; the player never blocks past one poll timeout.
- Shutdown cannot close an audio device while the player is using it; repeated
  shutdown is harmless; post-shutdown `Initialize` is a documented no-op.
- Mixer behavior is covered by deterministic tests that require no audio
  hardware and no tasks.
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
- In-process reinitialization after shutdown.
