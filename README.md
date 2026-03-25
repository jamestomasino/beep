# beep

`beep` is a Linux-first Ada CLI project (in migration) for activity-driven sonification.

## Build

```bash
source ~/.profile
alr update
alr build
```

## Run

```bash
./obj/beep_main --help
./obj/beep_main --profile=noisy --no-cpu --audio-null
./obj/beep_main --debug-events --audio-bell
```

Use `--stats` to emit periodic `[stats ...]` lines with per-kind events/sec.

Send `SIGHUP` to a running process to reload config from disk:

```bash
kill -HUP <beep_pid>
```

## Tests

```bash
./obj/beep_core_tests
./obj/beep_config_tests
./scripts/prove.sh
```

## Notes

- System/tool dependencies are declared in `alire.toml`.
- Current implementation includes:
  - Ada core mapping/config with tests
  - Initial SPARK proof target (`beep-core-safety`) with `gnatprove`
  - Linux `/proc` samplers (cpu/system/net)
  - X11 activity sampler (keyboard/mouse movement)
  - Native audio output via ALSA, with terminal bell fallback
  - Signal tuning knobs via config (`signal_*` weights/min-gaps/source factors)
