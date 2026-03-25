#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APPDIR="$ROOT/build/AppDir"
OUTDIR="$ROOT/build/out"
TOOLDIR="$ROOT/build/tools"

download_tool() {
  local url="$1"
  local out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -LfsS "$url" -o "$out"
    return 0
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -qO "$out" "$url"
    return 0
  fi
  return 1
}

ensure_tool() {
  local cmd="$1"
  local url="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    command -v "$cmd"
    return 0
  fi
  mkdir -p "$TOOLDIR"
  local local_bin="$TOOLDIR/$cmd"
  if [[ ! -x "$local_bin" ]]; then
    echo "$cmd not found in PATH, downloading local copy..."
    download_tool "$url" "$local_bin" || {
      echo "Failed to download $cmd (need curl or wget)"
      exit 1
    }
    chmod +x "$local_bin"
  fi
  echo "$local_bin"
}

LINUXDEPLOY_BIN="$(ensure_tool linuxdeploy 'https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage')"
APPIMAGETOOL_BIN="$(ensure_tool appimagetool 'https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage')"

mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/share/applications" "$APPDIR/usr/share/icons/hicolor/256x256/apps" "$APPDIR/usr/share/metainfo" "$OUTDIR"
# Clean stale metainfo files from previous incremental AppDir runs.
rm -f "$APPDIR"/usr/share/metainfo/*.appdata.xml "$APPDIR"/usr/share/metainfo/*.metainfo.xml 2>/dev/null || true

( cd "$ROOT" && v . )
cp "$ROOT/beep" "$APPDIR/usr/bin/beep"
cp "$ROOT/scripts/beep-tray.sh" "$APPDIR/usr/bin/beep-tray"

if command -v gcc >/dev/null 2>&1 && command -v pkg-config >/dev/null 2>&1 && pkg-config --exists gtk+-3.0; then
  mkdir -p "$ROOT/build"
  gcc -O2 -Wno-deprecated-declarations "$ROOT/tray/gtk_tray.c" -o "$ROOT/build/beep-tray-gtk" $(pkg-config --cflags --libs gtk+-3.0)
fi
if [[ -x "$ROOT/build/beep-tray-gtk" ]]; then
  cp "$ROOT/build/beep-tray-gtk" "$APPDIR/usr/bin/beep-tray-gtk"
fi
if command -v gcc >/dev/null 2>&1 && command -v pkg-config >/dev/null 2>&1 && pkg-config --exists ayatana-appindicator3-0.1 gtk+-3.0; then
  mkdir -p "$ROOT/build"
  gcc -O2 "$ROOT/tray/appindicator_tray.c" -o "$ROOT/build/beep-tray-appindicator" -DUSE_AYATANA $(pkg-config --cflags --libs ayatana-appindicator3-0.1 gtk+-3.0)
elif command -v gcc >/dev/null 2>&1 && command -v pkg-config >/dev/null 2>&1 && pkg-config --exists appindicator3-0.1 gtk+-3.0; then
  mkdir -p "$ROOT/build"
  gcc -O2 "$ROOT/tray/appindicator_tray.c" -o "$ROOT/build/beep-tray-appindicator" -DUSE_APPINDICATOR $(pkg-config --cflags --libs appindicator3-0.1 gtk+-3.0)
fi
if [[ -x "$ROOT/build/beep-tray-appindicator" ]]; then
  cp "$ROOT/build/beep-tray-appindicator" "$APPDIR/usr/bin/beep-tray-appindicator"
fi

cat > "$APPDIR/usr/share/applications/io.github.jamestomasino.beep.desktop" <<'DESK'
[Desktop Entry]
Type=Application
Name=beep
Comment=Retro activity sonifier with local controls
Exec=beep-tray
Icon=beep
Terminal=false
Categories=AudioVideo;Audio;
Actions=OpenControl;StopDaemon;

[Desktop Action OpenControl]
Name=Open Beep Controls
Exec=beep-tray --open-ui

[Desktop Action StopDaemon]
Name=Stop Beep
Exec=beep-tray --stop
DESK

cat > "$APPDIR/usr/share/metainfo/io.github.jamestomasino.beep.metainfo.xml" <<'META'
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>io.github.jamestomasino.beep</id>
  <name>beep</name>
  <summary>Retro activity sonifier with live controls</summary>
  <metadata_license>MIT</metadata_license>
  <project_license>MIT</project_license>
  <url type="homepage">https://github.com/jamestomasino/beep</url>
  <developer id="io.github.jamestomasino">
    <name>James Tomasino</name>
  </developer>
  <description>
    <p>beep turns system activity into retro-futuristic procedural sounds and provides live controls for intensity and behavior.</p>
  </description>
  <launchable type="desktop-id">io.github.jamestomasino.beep.desktop</launchable>
  <content_rating type="oars-1.1" />
  <categories>
    <category>AudioVideo</category>
    <category>Audio</category>
  </categories>
</component>
META

if command -v convert >/dev/null 2>&1; then
  convert -size 256x256 xc:'#10161f' \
    -fill '#79d6ff' -draw 'roundrectangle 48,48 208,208 18,18' \
    -fill '#0d1219' -draw 'rectangle 64,96 192,208' \
    -fill '#dff4ff' -draw 'rectangle 84,118 116,150' \
    -fill '#dff4ff' -draw 'rectangle 140,118 172,150' \
    -fill '#79d6ff' -draw 'rectangle 112,24 144,48' \
    -fill '#79d6ff' -draw 'rectangle 106,16 150,24' \
    "PNG8:$APPDIR/usr/share/icons/hicolor/256x256/apps/beep.png"
else
  cat > "$APPDIR/usr/share/icons/hicolor/256x256/apps/beep.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
  <rect width="256" height="256" fill="#10161f"/>
  <rect x="48" y="48" width="160" height="160" rx="18" fill="#79d6ff"/>
  <rect x="64" y="96" width="128" height="112" fill="#0d1219"/>
  <rect x="84" y="118" width="32" height="32" fill="#dff4ff"/>
  <rect x="140" y="118" width="32" height="32" fill="#dff4ff"/>
  <rect x="112" y="24" width="32" height="24" fill="#79d6ff"/>
  <rect x="106" y="16" width="44" height="8" fill="#79d6ff"/>
</svg>
SVG
fi

"$LINUXDEPLOY_BIN" --appimage-extract-and-run --appdir "$APPDIR" -d "$APPDIR/usr/share/applications/io.github.jamestomasino.beep.desktop" -i "$APPDIR/usr/share/icons/hicolor/256x256/apps/beep.png"
# linuxdeploy may rewrite ELF metadata; keep the original daemon binary to avoid runtime instability.
cp "$ROOT/beep" "$APPDIR/usr/bin/beep"
"$APPIMAGETOOL_BIN" --appimage-extract-and-run "$APPDIR" "$OUTDIR/beep-x86_64.AppImage"

echo "Built: $OUTDIR/beep-x86_64.AppImage"
