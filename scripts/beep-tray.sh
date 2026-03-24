#!/usr/bin/env bash
set -euo pipefail

BEEP_BIN="${BEEP_BIN:-$(dirname "$0")/../beep}"
if [[ ! -x "$BEEP_BIN" ]]; then
  BEEP_BIN="${BEEP_BIN:-beep}"
fi
IPC_ADDR="${BEEP_IPC_ADDR:-127.0.0.1:48777}"
UI_ADDR="${BEEP_UI_ADDR:-127.0.0.1:48778}"
export BEEP_IPC_ADDR="$IPC_ADDR"
export BEEP_UI_ADDR="$UI_ADDR"

# Ensure daemon exists.
if ! "$BEEP_BIN" --ctl=get_state >/dev/null 2>&1; then
  "$BEEP_BIN" >/tmp/beep-daemon.log 2>&1 &
  sleep 1
fi

if ! command -v yad >/dev/null 2>&1; then
  URL="http://$UI_ADDR/"
  echo "yad not found; using built-in web UI at $URL" >&2
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$URL" >/dev/null 2>&1 || true
  fi
  echo "Open: $URL"
  exit 0
fi

MENU="Toggle Enabled!$BEEP_BIN --ctl=toggle:enabled"
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
  --image="audio-volume-high" \
  --text="beep" \
  --command="$BEEP_BIN --ctl=get_state" \
  --menu="$MENU"
