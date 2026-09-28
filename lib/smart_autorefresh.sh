#!/bin/bash
set -u -o pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin"
export PATH

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/lib/common.sh"

load_config
ensure_state_dir

LOG_PREFIX="[WeChat2 AutoRefresh]"
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S %Z') $LOG_PREFIX $*"
}

LOCK_DIR="$STATE_DIR/autorefresh.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  OLD_PID="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
  if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
    log "Another refresh process is already running (pid $OLD_PID); skipping."
    exit 0
  fi
  rm -rf "$LOCK_DIR"
  mkdir "$LOCK_DIR" || exit 0
fi
echo "$$" > "$LOCK_DIR/pid"
trap 'rm -rf "$LOCK_DIR"' EXIT INT TERM

THRESHOLD_SECONDS=86400
NOW="$(date +%s)"

if EXPIRY="$(read_profile_expiration_epoch 2>/dev/null)"; then
  REMAINING=$((EXPIRY - NOW))
  if [ "$REMAINING" -gt "$THRESHOLD_SECONDS" ]; then
    HOURS=$((REMAINING / 3600))
    log "Signature still has about ${HOURS}h remaining; outside the final 24h window. No signing/device retry."
    exit 0
  fi

  if [ "$REMAINING" -gt 0 ]; then
    HOURS=$((REMAINING / 3600))
    log "Inside final 24h window (${HOURS}h remaining); attempting refresh."
  else
    log "Recorded provisioning profile is expired; attempting refresh."
  fi
else
  log "No recorded provisioning expiration found; attempting refresh now to establish state."
fi

DEVICE_ID="$(read_autorefresh_device_id 2>/dev/null || true)"
if [ -z "$DEVICE_ID" ]; then
  DEVICE_ID="$(read_last_device_id 2>/dev/null || true)"
fi

if [ -z "$DEVICE_ID" ]; then
  log "No target iPhone is configured. Reinstall the smart auto-refresh schedule."
  exit 75
fi

if ! list_physical_iphones | grep -Fq "($DEVICE_ID)"; then
  log "Target iPhone $DEVICE_ID is offline/not visible. Will retry on the next hourly run."
  exit 75
fi

export WECHAT2_NONINTERACTIVE=1
export WECHAT2_DEVICE_ID="$DEVICE_ID"

log "Target iPhone is online; starting unattended re-sign/install."

if "$ROOT/install_wechat2.command"; then
  NEW_EXPIRY="$(profile_expiration_human 2>/dev/null || echo unknown)"
  log "Refresh succeeded. New provisioning expiration: $NEW_EXPIRY"
  exit 0
else
  RC=$?
  log "Refresh failed with exit code $RC. Schedule remains installed; will retry next hour."
  exit "$RC"
fi
