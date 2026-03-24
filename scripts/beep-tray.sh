#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

BEEP_BIN="${BEEP_BIN:-$ROOT_DIR/beep}"
if [[ ! -x "$BEEP_BIN" ]]; then
  BEEP_BIN="beep"
fi

IPC_ADDR="${BEEP_IPC_ADDR:-127.0.0.1:48777}"
UI_ADDR="${BEEP_UI_ADDR:-127.0.0.1:48778}"
URL="http://$UI_ADDR/"

export BEEP_IPC_ADDR="$IPC_ADDR"
export BEEP_UI_ADDR="$UI_ADDR"

ensure_daemon() {
  if ! "$BEEP_BIN" --ctl=get_state >/dev/null 2>&1; then
    "$BEEP_BIN" >/tmp/beep-daemon.log 2>&1 &
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
  "$BEEP_BIN" --ctl=quit >/dev/null 2>&1 || true
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

if command -v yad >/dev/null 2>&1; then
  MENU="Open Controls!xdg-open $URL"
  MENU+="|Toggle Enabled!$BEEP_BIN --ctl=toggle:enabled"
  MENU+="|Profile Normal!$BEEP_BIN --ctl=set:profile=normal"
  MENU+="|Profile Calm!$BEEP_BIN --ctl=set:profile=calm"
  MENU+="|Profile Noisy!$BEEP_BIN --ctl=set:profile=noisy"
  MENU+="|Vol 25%!$BEEP_BIN --ctl=set:master_volume=0.25"
  MENU+="|Vol 50%!$BEEP_BIN --ctl=set:master_volume=0.50"
  MENU+="|Vol 75%!$BEEP_BIN --ctl=set:master_volume=0.75"
  MENU+="|Vol 100%!$BEEP_BIN --ctl=set:master_volume=1.00"
  MENU+="|Ambient Low!$BEEP_BIN --ctl=set:ambient_level=0.40"
  MENU+="|Ambient Mid!$BEEP_BIN --ctl=set:ambient_level=0.70"
  MENU+="|Ambient Full!$BEEP_BIN --ctl=set:ambient_level=1.00"
  MENU+="|Burst Sparse!$BEEP_BIN --ctl=set:burst_density=0.30"
  MENU+="|Burst Medium!$BEEP_BIN --ctl=set:burst_density=0.60"
  MENU+="|Burst Dense!$BEEP_BIN --ctl=set:burst_density=1.00"
  MENU+="|CPU Source!$BEEP_BIN --ctl=toggle:enable_cpu"
  MENU+="|System Source!$BEEP_BIN --ctl=toggle:enable_system"
  MENU+="|Network Source!$BEEP_BIN --ctl=toggle:enable_network"
  MENU+="|Debug Events!$BEEP_BIN --ctl=toggle:log_events"
  MENU+="|Save Config!$BEEP_BIN --ctl=save_config"
  MENU+="|Quit Beep!$BEEP_BIN --ctl=quit"

  exec yad --notification \
    --image="computer" \
    --text="beep" \
    --command="xdg-open $URL" \
    --menu="$MENU"
fi

if run_native_tray; then
  exit 0
fi

echo "No tray backend found (yad/gtk helper)." >&2
echo "beep is running in background." >&2
echo "Open controls: $URL" >&2
echo "Stop daemon: $BEEP_BIN --ctl=quit" >&2
open_ui
