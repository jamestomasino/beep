#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APPDIR="$ROOT/build/AppDir"
OUTDIR="$ROOT/build/out"

command -v linuxdeploy >/dev/null 2>&1 || { echo "linuxdeploy not found"; exit 1; }
command -v appimagetool >/dev/null 2>&1 || { echo "appimagetool not found"; exit 1; }

mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/share/applications" "$APPDIR/usr/share/icons/hicolor/256x256/apps" "$OUTDIR"

( cd "$ROOT" && v . )
cp "$ROOT/beep" "$APPDIR/usr/bin/beep"
cp "$ROOT/scripts/beep-tray.sh" "$APPDIR/usr/bin/beep-tray"

if command -v gcc >/dev/null 2>&1 && command -v pkg-config >/dev/null 2>&1 && pkg-config --exists gtk+-3.0; then
  mkdir -p "$ROOT/build"
  gcc -O2 "$ROOT/tray/gtk_tray.c" -o "$ROOT/build/beep-tray-gtk" $(pkg-config --cflags --libs gtk+-3.0)
fi
if [[ -x "$ROOT/build/beep-tray-gtk" ]]; then
  cp "$ROOT/build/beep-tray-gtk" "$APPDIR/usr/bin/beep-tray-gtk"
fi

cat > "$APPDIR/usr/share/applications/beep.desktop" <<'DESK'
[Desktop Entry]
Type=Application
Name=beep
Comment=Retro activity sonifier with local controls
Exec=beep-tray
Icon=beep
Terminal=false
Categories=Audio;Utility;
Actions=OpenControl;StopDaemon;

[Desktop Action OpenControl]
Name=Open Beep Controls
Exec=beep-tray --open-ui

[Desktop Action StopDaemon]
Name=Stop Beep
Exec=beep-tray --stop
DESK

cat > "$APPDIR/usr/share/icons/hicolor/256x256/apps/beep.png.base64" <<'B64'
iVBORw0KGgoAAAANSUhEUgAAAQAAAAEACAIAAADTED8xAAABQElEQVR4nO3TMQEAIAzAMMC/5+ECjiYKenbPzCwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA4N0Bf3AAAZo8fY8AAAAASUVORK5CYII=
B64
base64 -d "$APPDIR/usr/share/icons/hicolor/256x256/apps/beep.png.base64" > "$APPDIR/usr/share/icons/hicolor/256x256/apps/beep.png"
rm -f "$APPDIR/usr/share/icons/hicolor/256x256/apps/beep.png.base64"

linuxdeploy --appdir "$APPDIR" -d "$APPDIR/usr/share/applications/beep.desktop" -i "$APPDIR/usr/share/icons/hicolor/256x256/apps/beep.png"
appimagetool "$APPDIR" "$OUTDIR/beep-x86_64.AppImage"

echo "Built: $OUTDIR/beep-x86_64.AppImage"
