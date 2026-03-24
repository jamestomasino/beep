# Tray + Control UI (Linux)

Control options are available in two modes:

- tray menu via `yad` (when installed)
- built-in web UI fallback (no extra dependency)

## Run

```bash
./scripts/beep-tray.sh
```

This script:

- starts `beep` daemon if not already running
- uses tray menu if `yad` is available
- otherwise opens the built-in web UI at `http://127.0.0.1:48778/`
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
Web UI address defaults to `127.0.0.1:48778`, override with `BEEP_UI_ADDR`.
