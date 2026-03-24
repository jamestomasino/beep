# Tray UI (Linux)

A practical tray UI is provided via `yad` and IPC controls.

## Install

```bash
sudo apt install -y yad
```

## Run

```bash
./scripts/beep-tray.sh
```

This script:

- starts `beep` daemon if not already running
- creates a tray icon with a popup menu
- sends live control commands to daemon via `--ctl`

## Controlled Options

- enable/disable playback
- profile (`calm|normal|noisy`)
- master volume
- ambient level
- burst density
- source toggles (`cpu/system/network`)
- debug event logging
- save current runtime controls to config
- quit daemon

IPC address defaults to `127.0.0.1:48777`, override with `BEEP_IPC_ADDR`.
