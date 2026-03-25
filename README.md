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
```

## Tests

```bash
./obj/beep_core_tests
./obj/beep_config_tests
```

## Notes

- System/tool dependencies are declared in `alire.toml`.
- Current implementation includes Ada core mapping and config parsing with tests.
- Linux sampler and audio backend ports are next migration steps.
