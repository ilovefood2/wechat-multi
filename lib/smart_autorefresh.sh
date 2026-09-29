#!/bin/bash
set -u -o pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin"
export PATH

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/lib/common.sh"

load_config
ensure_state_dir

MODE="${1:-retry}"
LOG_PREFIX="[WeChat2 AutoRefresh]"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S %Z') $LOG_PREFIX $*"
}

target_device() {
  local d
  d="$(read_autorefresh_device_id 2>/dev/null || true)"
  [ -n "$d" ] || d="$(read_last_device_id 2>/dev/null || true)"
  printf '%s\n' "$d"
}

activate_retry() {
  /bin/bash "$ROOT/setup_wechat2_smart_autorefresh.sh" activate-retry
}

reconcile_schedule() {
  /bin/bash "$ROOT/setup_wechat2_smart_autorefresh.sh" reconcile
}

run_wakeup() {
  local device expiry now due
  device="$(target_device)"
  if [ -z "$device" ]; then
    log "No target iPhone is configured; install the smart auto-refresh schedule again."
    exit 75
  fi

  now="$(date +%s)"
  expiry="$(read_install_receipt_expiration_epoch "$device" 2>/dev/null || true)"

  if [ -n "$expiry" ]; then
    due=$((expiry - AUTO_REFRESH_WINDOW_SECONDS))
    if [ "$now" -lt "$due" ]; then
      log "Wake-up check ran before renewal window; no Xcode/device/signing work is needed."
      exit 0
    fi
    log "Renewal window is open; enabling hourly retry worker."
  else
    log "No verified successful-install receipt exists; enabling hourly retry worker."
  fi

  activate_retry
}

run_retry() {
  local lock_dir old_pid device old_expiry new_expiry now due rc

  lock_dir="$STATE_DIR/autorefresh.lock"
  if ! mkdir "$lock_dir" 2>/dev/null; then
    old_pid="$(cat "$lock_dir/pid" 2>/dev/null || true)"
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
      log "Another refresh process is already running (pid $old_pid); skipping."
      exit 0
    fi
    rm -rf "$lock_dir"
    mkdir "$lock_dir" || exit 0
  fi
  echo "$$" > "$lock_dir/pid"
  trap 'rm -rf "$lock_dir"' EXIT INT TERM

  recover_pending_profile_cache_transactions >/dev/null 2>&1 || true

  device="$(target_device)"
  if [ -z "$device" ]; then
    log "No target iPhone is configured. Retry remains enabled."
    exit 75
  fi

  now="$(date +%s)"
  old_expiry="$(read_install_receipt_expiration_epoch "$device" 2>/dev/null || true)"

  if [ -n "$old_expiry" ]; then
    due=$((old_expiry - AUTO_REFRESH_WINDOW_SECONDS))
    if [ "$now" -lt "$due" ]; then
      log "Verified installed profile is outside the renewal window; returning to quiet mode."
      reconcile_schedule
      exit 0
    fi
  fi

  if ! list_physical_iphones | grep -Fq "($device)"; then
    log "Target iPhone $device is offline/not visible. Hourly retry remains enabled."
    exit 75
  fi

  export WECHAT2_NONINTERACTIVE=1
  export WECHAT2_DEVICE_ID="$device"
  export WECHAT2_AUTOREFRESH_CONTEXT=1

  if [ -n "$old_expiry" ]; then
    export WECHAT2_REQUIRE_EXPIRY_ADVANCE=1
    export WECHAT2_PREVIOUS_EXPIRY="$old_expiry"
    log "Starting validated renewal. New effective expiry must advance beyond $(date -r "$old_expiry" '+%Y-%m-%d %H:%M:%S %Z')."
  else
    unset WECHAT2_REQUIRE_EXPIRY_ADVANCE WECHAT2_PREVIOUS_EXPIRY 2>/dev/null || true
    log "No verified install receipt yet; performing one install to establish validated expiry state."
  fi

  "$ROOT/install_wechat2.command"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    log "Refresh/install failed with exit code $rc. Installed-expiry receipt was not advanced; hourly retry remains enabled."
    exit "$rc"
  fi

  new_expiry="$(read_install_receipt_expiration_epoch "$device" 2>/dev/null || true)"
  if [ -z "$new_expiry" ]; then
    log "Installer returned success but no verified install receipt is readable. Hourly retry remains enabled."
    exit 70
  fi

  if [ -n "$old_expiry" ] && [ "$new_expiry" -le "$old_expiry" ]; then
    log "Renewal receipt did not advance expiration ($old_expiry -> $new_expiry). Hourly retry remains enabled."
    exit 70
  fi

  log "RENEWAL CONFIRMED: effective installed expiry is now $(date -r "$new_expiry" '+%Y-%m-%d %H:%M:%S %Z')."
  log "Reprogramming one-shot wake-up for expiry minus the renewal window."
  reconcile_schedule
}

case "$MODE" in
  wakeup)
    run_wakeup
    ;;
  retry)
    run_retry
    ;;
  *)
    echo "Usage: $0 [wakeup|retry]" >&2
    exit 2
    ;;
esac
