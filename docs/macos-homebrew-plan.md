# macOS + Homebrew Enablement Plan

## Goal
Run `beep` as a CLI on modern macOS (Apple Silicon and Intel), then distribute via Homebrew.

## Current status
- Completed:
  - Linux-only linker flags removed from `beep.gpr`.
  - `beep` now supports portable `bell`/`null` audio and macOS native output (`afplay`) in `src/audio/beep-audio.adb`.
  - New cross-platform sampler abstraction in `src/platform/beep-platform-samplers.*` with Linux + macOS probe paths.
  - macOS interactive activity signal added via `IOHIDSystem` (`HIDIdleTime`) polling; no sudo required.
  - `alire.toml` no longer depends on `libx11`/`pkg_config`.
- Remaining:
  - Improve macOS interactive input fidelity/attribution (true keyboard vs mouse classification).
  - Replace `afplay` bridge with a direct CoreAudio/miniaudio render path.

## Current blockers
- Linux-only sampler dependency in main:
  - `src/main.adb` imports and uses `Beep.Linux.Samplers` directly.
- Linux-oriented sampling implementation:
  - `src/linux/beep-linux-samplers.adb` still uses `/proc/*` for activity sources.
- No native macOS audio backend yet:
  - `src/audio/beep-audio.adb` currently provides portable `bell`/`null` only.

## Phase 1: Build and run on macOS (minimum viable)
1. Add a platform sampler abstraction.
   - New package: `Beep.Platform.Samplers`.
   - Linux implementation delegates to existing `Beep.Linux.Samplers`.
   - Darwin implementation initially emits no samples (safe no-op), preserving CLI behavior.
2. Move Linux/Wayland-specific warnings behind a Linux platform guard.
3. Add native audio backend.
   - Current portable build supports `null` and `bell`.
   - Add miniaudio/CoreAudio for macOS sound synthesis.
4. Move from Linux sampler package name to a platform abstraction package.
   - Introduce `Beep.Platform.Samplers` and route OS-specific implementations.

Acceptance:
- `alr build` succeeds on macOS.
- `beep --version`, `beep --help`, `beep --audio-bell`, `beep --audio-null` run on macOS.

## Phase 2: Restore feature parity on macOS
1. Implement macOS samplers for CPU/system/network/process activity.
   - Candidate APIs: `sysctl`, `host_statistics`, `libproc`, routing table counters.
2. Implement interactive input sampler for macOS.
   - Candidate APIs: Quartz Event Taps / CGEvent source state.
3. Add macOS native audio backend.
   - Preferred: miniaudio/CoreAudio backend; keep ALSA backend for Linux.

Acceptance:
- Activity events are produced on macOS without Linux `/proc`.
- Interactive signals (keyboard/mouse) work with documented permission prompts.

## Phase 3: Homebrew distribution
1. Ship tagged source releases (and optionally prebuilt release artifacts).
2. Create dedicated tap, e.g. `jamestomasino/homebrew-beep`.
3. Add `Formula/beep.rb` with build + test stanza.
   - Build from source via `alr build` (or direct `gprbuild` once dependency story is stable).
4. Enable bottles via tap workflow and publish per-arch macOS bottles.
5. Document install paths:
   - `brew install jamestomasino/beep/beep`

Acceptance:
- Clean install on macOS via Homebrew.
- Formula test passes (`beep --version`).

## Open decisions
- Do we require Apple Silicon-native toolchain now, or allow Rosetta for first mac release?
- Is Phase 1 acceptable with reduced telemetry (no keyboard/mouse/system sampling yet)?
- Is miniaudio the long-term cross-platform audio backend, replacing ALSA-specific path?
