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

By default the CLI now emits periodic `[stats ...]` lines with per-kind events/sec.
Disable with config key `log_stats=false`.

## Tests

```bash
./obj/beep_core_tests
./obj/beep_config_tests
```

## Notes

- System/tool dependencies are declared in `alire.toml`.
- Current implementation includes:
  - Ada core mapping/config with tests
  - Linux `/proc` samplers (cpu/system/net)
  - X11 activity sampler (keyboard/mouse movement)
  - Native audio output via ALSA, with terminal bell fallback
  - Signal tuning knobs via config (`signal_*` weights/min-gaps/source factors)
