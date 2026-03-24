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

Runtime notes:

- if `yad` is missing, control falls back to built-in web UI
- X11 global input paths still require X11-related runtime support
- on Wayland sessions, app continues with cpu/system/network samplers
