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
- `beep-tray` tray launcher script

Runtime notes:

- tray script requires `yad` on target system
- X11 global input paths still require X11-related runtime support
