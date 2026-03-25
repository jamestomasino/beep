# beep

`beep` is a Linux-first Ada CLI that turns system and activity signals into a layered ambient soundscape. *beep beep*

It currently combines:
- Linux `/proc` samplers (CPU/system/network/load/disk/pressure)
- X11 activity sampling (keyboard/mouse where available)
- Native Ada mapping/synthesis logic with ALSA output (and null/bell backends)
- Runtime tuning via config reload (`SIGHUP`)

## Build

```bash
alr update
alr build
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
- Signal tuning and audio mix controls are configurable via `signal_*` and `audio_mix_*` keys.
