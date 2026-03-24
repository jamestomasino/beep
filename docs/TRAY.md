# Tray + Control UI (Linux)

Control options are available in three modes:

- tray menu via `yad` (when installed)
- native GTK tray helper fallback (`beep-tray-gtk`, auto-built when GTK dev libs are available)
- built-in web UI fallback (always available)

## Run

```bash
./scripts/beep-tray.sh
```

This script:

- starts `beep` daemon if not already running
- uses tray menu if `yad` is available
- otherwise uses native GTK tray helper when available
- otherwise opens the built-in web UI at `http://127.0.0.1:48778/`
- sends live control commands to daemon via `--ctl`

## Utility Modes

```bash
./scripts/beep-tray.sh --open-ui
./scripts/beep-tray.sh --stop
```

- `--open-ui`: ensure daemon is running and open web controls
- `--stop`: send daemon quit request

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
Web UI address defaults to `127.0.0.1:48778`, override with `BEEP_UI_ADDR`.
