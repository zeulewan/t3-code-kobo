#!/bin/sh
set -eu

BASE="${T3_KOBO_BRIDGE_DIR:-$HOME/.t3/kobo-bridge}"
SCRIPT="${T3_KOBO_BRIDGE_SCRIPT:-$BASE/t3-kobo-bridge.mjs}"
PIDFILE="$BASE/bridge.pid"
LOG="$BASE/bridge.log"

mkdir -p "$BASE"

if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  kill "$(cat "$PIDFILE")" 2>/dev/null || true
  sleep 1
fi

: > "$LOG"
setsid env \
  T3_KOBO_BRIDGE_HOST="${T3_KOBO_BRIDGE_HOST:-127.0.0.1}" \
  T3_KOBO_BRIDGE_PORT="${T3_KOBO_BRIDGE_PORT:-18891}" \
  T3_KOBO_TARGET="${T3_KOBO_TARGET:-}" \
  node "$SCRIPT" >>"$LOG" 2>&1 < /dev/null &
echo $! > "$PIDFILE"
