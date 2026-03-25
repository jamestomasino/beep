# beep

`beep` is a Linux-first Ada CLI that turns system and activity signals into a layered ambient soundscape. 

*beep beep*

It currently combines:
- Linux `/proc` samplers (CPU/system/network/load/disk/pressure)
- X11 activity sampling (keyboard/mouse where available)
- Native Ada mapping/synthesis logic with ALSA output (and null/bell backends)
- Runtime tuning via config reload (`SIGHUP`)

## Dependencies

`beep` links against X11 and ALSA:
- `libX11` (`-lX11`)
- `libasound` (`-lasound`)

Install build dependencies:

Ubuntu/Debian:

```bash
sudo apt update
sudo apt install -y build-essential pkg-config libx11-dev libasound2-dev
```

Fedora:

```bash
sudo dnf install -y gcc pkgconf-pkg-config xorg-x11-devel alsa-lib-devel
```

Arch Linux:

```bash
sudo pacman -S --needed base-devel pkgconf libx11 alsa-lib
```

Runtime-only (if you copy a prebuilt binary):

Ubuntu/Debian:

```bash
sudo apt install -y libx11-6 libasound2
```

Fedora:

```bash
sudo dnf install -y libX11 alsa-lib
```

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

Install Alire:

```bash
curl -sSf https://alire.ada.dev/install.sh | sh
```

If you prefer distro packages, check your distribution repositories for `alire`.

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
