# beep

`beep` is a Linux-first Ada CLI that turns system and activity signals into a layered ambient soundscape. 

*beep beep*

It currently combines:
- Platform samplers via `Beep.Platform.Samplers`:
  - Linux: `/proc` CPU/system/network sources
  - macOS: `sysctl`/`ps`/`memory_pressure`/`netstat` sources plus `IOHIDSystem` idle-time input activity
- Portable `bell`/`null` audio backends plus macOS native streaming output via CoreAudio
- Runtime tuning via config reload (`SIGHUP`)

## Monitored Signals by Platform

| Feature   | Linux | macOS |
|-----------|:-----:|:-----:|
| Keyboard  | X     | X     |
| Mouse     | X     | X     |
| CPU       | X     | X     |
| Process   | X     | X     |
| Memory    | X     | X     |
| System    | X     | X     |
| Network   | X     | X     |

Notes:
- `Keyboard`/`Mouse` require interactive sampling enabled (`enable_x11=true`).
- On Linux this uses X11 activity sources; on macOS it uses `IOHIDSystem` idle-time activity.

## Homebrew Install (macOS)

```bash
brew tap jamestomasino/beep
brew install jamestomasino/beep/beep
```

Verify:

```bash
beep --version
```

## Dependencies

General build dependencies:

Ubuntu/Debian:

```bash
sudo apt update
sudo apt install -y build-essential
```

Fedora:

```bash
sudo dnf install -y gcc
```

Arch Linux:

```bash
sudo pacman -S --needed base-devel
```

No external runtime libraries are currently required for the portable `bell`/`null` backends.

## Toolchain

You need:
- GNAT (Ada compiler/toolchain)
- Alire (`alr`, Ada package manager/build frontend)

Ubuntu/Debian:

```bash
sudo apt update
sudo apt install -y gnat
```

Fedora:

```bash
sudo dnf install -y gcc-gnat
```

Arch Linux:

```bash
sudo pacman -S --needed gcc-ada
```

Install Alire (recommended: use the latest release from):

```bash
https://github.com/alire-project/alire/releases/latest
```

If you prefer distro packages, check your distribution repositories for `alire`.

## Build

```bash
alr update
alr build
```

On macOS builds, select Darwin sources explicitly:

```bash
BEEP_OS=darwin alr update
BEEP_OS=darwin alr build
```

Main binary output:

```bash
./obj/beep
```

## Install

Install for current user (`~/.local/bin/beep`):

```bash
mkdir -p ~/.local/bin
install -m 0755 ./obj/beep ~/.local/bin/beep
```

Install system-wide (`/usr/local/bin/beep`):

```bash
sudo install -m 0755 ./obj/beep /usr/local/bin/beep
```

Verify:

```bash
beep --version
```

Uninstall:

```bash
rm -f ~/.local/bin/beep
# or
sudo rm -f /usr/local/bin/beep
```

## macOS + Homebrew (Binary Releases)

This repo includes a tag-triggered GitHub Actions workflow at
`.github/workflows/release-macos.yml` that builds macOS binaries and
publishes them as GitHub Release assets.

Use those assets from a custom Homebrew tap formula for precompiled installs.
See:

- `docs/homebrew-binary-release.md`
- `docs/macos-homebrew-plan.md`

## Run

```bash
beep --help
beep --version
beep --profile=noisy --no-cpu --audio-null
beep --debug-events --audio-bell
beep --quiet
beep --silent
```

Use `--stats` to emit periodic `[stats ...]` lines with per-kind events/sec.

Send `SIGHUP` to a running process to reload config from disk:

```bash
kill -HUP <beep_pid>
```

## Config

Runtime config is read from `~/.config/beep/config.conf` by default (or `--config=<path>`).
The file format is `key=value` with `#` comments.

Common runtime keys:

```ini
profile=normal
enable_cpu=true
enable_system=true
enable_network=true
enable_x11=false
log_events=false
log_stats=false
stats_interval_ms=1000
debug_cpu=false
debug_fake_input=false
audio_backend=miniaudio
# macOS native streaming output options: coreaudio | native | miniaudio
# macOS interactive input sampler (IOHIDSystem idle time):
enable_x11=true
master_volume=1.0
ambient_level=1.0
burst_density=1.0
```

Engine mapping keys:

```ini
keyboard_threshold=0.25
mouse_threshold=0.20
keyboard_yip_intensity=0.72
keyboard_yip_chance=0.38
keyboard_chirp_chance=0.20
mouse_flick_intensity=0.65
mouse_flick_chance=0.33
mouse_click_zap_chance=1.00
cpu_active_cutoff=0.22
cpu_busy_cutoff=0.62
hum_active_max=0.68
hum_base_chance=0.88
hum_gain_scale=0.58
cpu_warble_active_chance=0.18
cpu_warble_busy_chance=0.44
process_threshold=0.15
memory_threshold=0.18
system_threshold=0.20
network_threshold=0.16
process_stutter_intensity=0.55
process_stutter_chance=0.35
memory_warble_intensity=0.44
memory_warble_chance=0.28
system_stutter_intensity=0.50
system_stutter_chance=0.42
network_chirp_intensity=0.60
network_chirp_chance=0.46
network_stutter_intensity=0.72
network_stutter_chance=0.30
min_gap_ms=70
cooldown_ms=180
```

Signal shaping keys:

```ini
signal_keyboard_weight=1.15
signal_mouse_weight=1.10
signal_cpu_weight=0.92
signal_process_weight=1.00
signal_memory_weight=0.96
signal_system_weight=0.78
signal_network_weight=0.95

signal_keyboard_min_gap_ms=18
signal_mouse_min_gap_ms=14
signal_cpu_min_gap_ms=60
signal_process_min_gap_ms=28
signal_memory_min_gap_ms=38
signal_system_min_gap_ms=48
signal_network_min_gap_ms=26

signal_mouse_click_boost=1.22
signal_x11_keyboard_boost=1.12
signal_psi_weight=0.72
signal_loadavg_weight=0.55
signal_disk_weight=0.90
```

Audio mix keys:

```ini
audio_mix_ambient_bed_drive=0.32
audio_mix_ambient_bed_max=0.30
audio_mix_ambient_bed_decay=0.992
audio_mix_mid_blend_min=0.16
audio_mix_mid_blend_max=0.52
audio_mix_mid_foreground_attenuation=0.55
```

Synth keys currently parsed by config loader:

```ini
hum_freq_min=68.0
hum_freq_max=118.0
drone_freq_min=52.0
drone_freq_max=92.0
wobble_freq_min=84.0
wobble_freq_max=140.0
ambient_noise_chance=0.40
ambient_noise_gain=0.08
ambient_blip_chance=0.36
ambient_blip_gain=0.10
cluster_steps_min=3
cluster_steps_max=12
cluster_spacing_min_ms=6
cluster_spacing_max_ms=16
stutter_steps_min=2
stutter_steps_max=5
stutter_spacing_min_ms=12
stutter_spacing_max_ms=26
```

## Tests

```bash
./obj/beep_core_tests
./obj/beep_config_tests
./scripts/prove.sh
```

## Notes

- System/tool dependencies are declared in `alire.toml`.
- Config defaults load from `~/.config/beep/config.conf` when present.
- Current implementation includes Ada core mapping/config tests and an initial SPARK proof target (`beep-core-safety`).
