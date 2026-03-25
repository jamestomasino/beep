#!/usr/bin/env bash
set -euo pipefail

SELF_PATH="$0"
if command -v readlink >/dev/null 2>&1; then
  RESOLVED="$(readlink -f "$0" 2>/dev/null || true)"
  if [[ -n "${RESOLVED:-}" ]]; then
    SELF_PATH="$RESOLVED"
  fi
fi
SCRIPT_DIR="$(cd "$(dirname "$SELF_PATH")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Resolve beep binary for both source-tree and AppImage layouts.
if [[ -z "${BEEP_BIN:-}" ]]; then
  if [[ -x "$SCRIPT_DIR/beep" ]]; then
    BEEP_BIN="$SCRIPT_DIR/beep"
  elif [[ -x "$ROOT_DIR/beep" ]]; then
    BEEP_BIN="$ROOT_DIR/beep"
  elif command -v beep >/dev/null 2>&1; then
    BEEP_BIN="$(command -v beep)"
  else
    echo "Could not locate beep binary. Tried: $SCRIPT_DIR/beep, $ROOT_DIR/beep, PATH" >&2
    exit 1
  fi
fi

IPC_ADDR="${BEEP_IPC_ADDR:-127.0.0.1:48777}"
UI_ADDR="${BEEP_UI_ADDR:-127.0.0.1:48778}"
URL="http://$UI_ADDR/"

export BEEP_IPC_ADDR="$IPC_ADDR"
export BEEP_UI_ADDR="$UI_ADDR"

beep_cmd() {
  env -u LD_LIBRARY_PATH "$BEEP_BIN" "$@"
}

ensure_daemon() {
  if ! beep_cmd --ctl=get_state >/dev/null 2>&1; then
    beep_cmd >/tmp/beep-daemon.log 2>&1 &
    sleep 1
  fi
}

open_ui() {
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$URL" >/dev/null 2>&1 || true
  fi
  echo "Open controls: $URL"
}

stop_daemon() {
  beep_cmd --ctl=quit >/dev/null 2>&1 || true
  echo "beep stop requested"
}

maybe_build_native_tray() {
  local out="$ROOT_DIR/build/beep-tray-gtk"
  local src="$ROOT_DIR/tray/gtk_tray.c"
  if [[ -x "$out" ]]; then
    return 0
  fi
  if ! command -v gcc >/dev/null 2>&1; then
    return 1
  fi
  if ! command -v pkg-config >/dev/null 2>&1; then
    return 1
  fi
  if ! pkg-config --exists gtk+-3.0; then
    return 1
  fi
  mkdir -p "$ROOT_DIR/build"
  gcc -O2 "$src" -o "$out" $(pkg-config --cflags --libs gtk+-3.0) >/dev/null 2>&1 || return 1
  return 0
}

maybe_build_appindicator_tray() {
  local out="$ROOT_DIR/build/beep-tray-appindicator"
  local src="$ROOT_DIR/tray/appindicator_tray.c"
  if [[ -x "$out" ]]; then
    return 0
  fi
  if ! command -v gcc >/dev/null 2>&1; then
    return 1
  fi
  if ! command -v pkg-config >/dev/null 2>&1; then
    return 1
  fi
  mkdir -p "$ROOT_DIR/build"
  if pkg-config --exists ayatana-appindicator3-0.1 gtk+-3.0; then
    gcc -O2 "$src" -o "$out" -DUSE_AYATANA $(pkg-config --cflags --libs ayatana-appindicator3-0.1 gtk+-3.0) >/dev/null 2>&1 || return 1
    return 0
  fi
  if pkg-config --exists appindicator3-0.1 gtk+-3.0; then
    gcc -O2 "$src" -o "$out" -DUSE_APPINDICATOR $(pkg-config --cflags --libs appindicator3-0.1 gtk+-3.0) >/dev/null 2>&1 || return 1
    return 0
  fi
  return 1
}

run_appindicator_tray() {
  local helper="${BEEP_TRAY_APPINDICATOR:-}"
  if [[ -z "$helper" ]]; then
    if [[ -x "$ROOT_DIR/build/beep-tray-appindicator" ]]; then
      helper="$ROOT_DIR/build/beep-tray-appindicator"
    elif command -v beep-tray-appindicator >/dev/null 2>&1; then
      helper="$(command -v beep-tray-appindicator)"
    fi
  fi
  if [[ -z "$helper" ]]; then
    maybe_build_appindicator_tray || return 1
    helper="$ROOT_DIR/build/beep-tray-appindicator"
  fi
  [[ -x "$helper" ]] || return 1
  "$helper" "$BEEP_BIN" "$URL"
}

run_native_tray() {
  local helper="${BEEP_TRAY_NATIVE:-}"
  if [[ -z "$helper" ]]; then
    if [[ -x "$ROOT_DIR/build/beep-tray-gtk" ]]; then
      helper="$ROOT_DIR/build/beep-tray-gtk"
    elif command -v beep-tray-gtk >/dev/null 2>&1; then
      helper="$(command -v beep-tray-gtk)"
    fi
  fi

  if [[ -z "$helper" ]]; then
    maybe_build_native_tray || return 1
    helper="$ROOT_DIR/build/beep-tray-gtk"
  fi

  [[ -x "$helper" ]] || return 1
  "$helper" "$BEEP_BIN" "$URL"
}

case "${1:-}" in
  --stop)
    stop_daemon
    exit 0
    ;;
  --open-ui)
    ensure_daemon
    open_ui
    exit 0
    ;;
esac

ensure_daemon

if run_appindicator_tray; then
  exit 0
fi

if command -v yad >/dev/null 2>&1; then
  BEEP_CTL="env -u LD_LIBRARY_PATH $BEEP_BIN"
  MENU="Open Controls!xdg-open $URL"
  MENU+="|Toggle Enabled!$BEEP_CTL --ctl=toggle:enabled"
  MENU+="|Profile Normal!$BEEP_CTL --ctl=set:profile=normal"
  MENU+="|Profile Calm!$BEEP_CTL --ctl=set:profile=calm"
  MENU+="|Profile Noisy!$BEEP_CTL --ctl=set:profile=noisy"
  MENU+="|Vol 25%!$BEEP_CTL --ctl=set:master_volume=0.25"
  MENU+="|Vol 50%!$BEEP_CTL --ctl=set:master_volume=0.50"
  MENU+="|Vol 75%!$BEEP_CTL --ctl=set:master_volume=0.75"
  MENU+="|Vol 100%!$BEEP_CTL --ctl=set:master_volume=1.00"
  MENU+="|Ambient Low!$BEEP_CTL --ctl=set:ambient_level=0.40"
  MENU+="|Ambient Mid!$BEEP_CTL --ctl=set:ambient_level=0.70"
  MENU+="|Ambient Full!$BEEP_CTL --ctl=set:ambient_level=1.00"
  MENU+="|Burst Sparse!$BEEP_CTL --ctl=set:burst_density=0.30"
  MENU+="|Burst Medium!$BEEP_CTL --ctl=set:burst_density=0.60"
  MENU+="|Burst Dense!$BEEP_CTL --ctl=set:burst_density=1.00"
  MENU+="|CPU Source!$BEEP_CTL --ctl=toggle:enable_cpu"
  MENU+="|System Source!$BEEP_CTL --ctl=toggle:enable_system"
  MENU+="|Network Source!$BEEP_CTL --ctl=toggle:enable_network"
  MENU+="|Debug Events!$BEEP_CTL --ctl=toggle:log_events"
  MENU+="|Save Config!$BEEP_CTL --ctl=save_config"
  MENU+="|Quit Beep!$BEEP_CTL --ctl=quit"

  exec yad --notification \
    --image="computer" \
    --text="beep" \
    --command="xdg-open $URL" \
    --menu="$MENU"
fi

if run_native_tray; then
  exit 0
fi

echo "No tray backend found (appindicator/yad/gtk helper)." >&2
echo "beep is running in background." >&2
echo "Open controls: $URL" >&2
echo "Stop daemon: $BEEP_BIN --ctl=quit" >&2
open_ui
