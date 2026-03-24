# beep

`beep` is a Linux-first V app inspired by classic retro activity sonifiers.
It runs in the background and maps real machine/input activity to procedural sci-fi sound cues.

## Current Scope

- Linux runtime
- X11 global keyboard/mouse sampler (`poll` + optional `xi2`)
- `/proc` CPU sampler
- `/proc` system churn sampler (process/context/memory pressure deltas)
- `/proc` network sampler
- Event engine with varied motif palettes (not fixed one-source/one-sound mapping)
- Realtime synthesis via `miniaudio`
- Optional sample-layer blending from `assets/samples/*.wav`
- Local control API (`--ctl`) for live runtime changes
- Tray launcher script (`scripts/beep-tray.sh`)

## Run

```bash
v run .
```

Useful flags:

- `--profile=<calm|normal|noisy>`
- `--config=<path>`
- `--no-cpu`
- `--no-system`
- `--no-net`
- `--x11-input` (requires build flag `-d x11_input`)
- `--x11-mode=<poll|xi2>` (`xi2` requires build flag `-d x11_xi2`)
- `--debug-events`
- `--debug-cpu`
- `--debug-fake-input` (testing only)
- `--audio-null`
- `--ipc-addr=<host:port>`
- `--no-ipc`
- `--ctl=<cmd>` (`get_state`, `quit`, `save_config`, `toggle:<key>`, `set:<key>=<value>`)

X11 input build dependencies:

```bash
sudo apt install -y libx11-dev
```

Optional XInput2 backend:

```bash
sudo apt install -y libxi-dev
v -d x11_input -d x11_xi2 run . --x11-input --x11-mode=xi2
```

## Config

Default config path:

`~/.config/beep/config.conf`

See [docs/CONFIG.md](docs/CONFIG.md).

## Tray UI

```bash
./scripts/beep-tray.sh
```

See [docs/TRAY.md](docs/TRAY.md).

## AppImage

```bash
./scripts/build_appimage.sh
```

See [docs/PACKAGING.md](docs/PACKAGING.md).

## Notes

- On Wayland, global input hooks are compositor-specific.
- Ambient motifs are long-form with slow fade-in/fade-out.
