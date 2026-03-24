# Packaging (AppImage)

Build script:

```bash
./scripts/build_appimage.sh
```

Requirements:

- `v`
- `linuxdeploy`
- `appimagetool`

Output:

- `build/out/beep-x86_64.AppImage`

The AppImage currently includes:

- `beep` daemon binary
- `beep-tray` control launcher script (tray if `yad`, web UI otherwise)
- `beep-tray-gtk` helper when build host has GTK3 dev toolchain

Runtime notes:

- desktop entry includes quick actions: `Open Beep Controls`, `Stop Beep`
- if `yad` is missing, `beep-tray-gtk` is attempted, then web UI fallback
- X11 global input paths still require X11-related runtime support
- on Wayland sessions, app continues with cpu/system/network samplers
