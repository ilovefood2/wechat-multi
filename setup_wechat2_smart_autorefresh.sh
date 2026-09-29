#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$DIR/lib/common.sh"

load_config
ensure_state_dir

WAKE_LABEL="com.ilovefood2.wechat2.autorefresh.wakeup"
RETRY_LABEL="com.ilovefood2.wechat2.autorefresh.retry"
LEGACY_LABEL="com.ilovefood2.wechat2.smart-autorefresh"

WAKE_PLIST="$HOME/Library/LaunchAgents/$WAKE_LABEL.plist"
RETRY_PLIST="$STATE_DIR/$RETRY_LABEL.plist"
LEGACY_PLIST="$HOME/Library/LaunchAgents/$LEGACY_LABEL.plist"
SCHEDULE_STATE="$STATE_DIR/autorefresh_schedule.json"
LOG="$HOME/Library/Logs/WeChat2SmartAutoRefresh.log"
RUNNER="$ROOT/lib/smart_autorefresh.sh"
DOMAIN="gui/$(id -u)"

loaded() {
  local label="$1"
  launchctl print "$DOMAIN/$label" >/dev/null 2>&1
}

bootout() {
  local label="$1"
  launchctl bootout "$DOMAIN/$label" >/dev/null 2>&1 || true
}

target_device() {
  local d
  d="$(read_autorefresh_device_id 2>/dev/null || true)"
  [ -n "$d" ] || d="$(read_last_device_id 2>/dev/null || true)"
  printf '%s\n' "$d"
}

write_schedule_state() {
  local device="$1"
  local expiry="$2"
  local due="$3"
  local mode="$4"

  python3 - "$SCHEDULE_STATE" "$device" "$expiry" "$due" "$mode" <<'PY'
import json, os, sys, tempfile, time
path, device, expiry, due, mode = sys.argv[1:6]
data = {
    "device": device,
    "expiry": int(expiry) if expiry else None,
    "due": int(due),
    "mode": mode,
    "updated_at": int(time.time()),
}
os.makedirs(os.path.dirname(path), exist_ok=True)
fd, tmp = tempfile.mkstemp(prefix=".schedule.", dir=os.path.dirname(path))
try:
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, indent=2, sort_keys=True)
        f.write("\n")
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)
finally:
    try:
        os.unlink(tmp)
    except FileNotFoundError:
        pass
PY
}

write_wake_plist() {
  local requested_due="$1"
  local now rounded
  now="$(date +%s)"

  # If already due, retain a near-future calendar event as a recovery hook.
  if [ "$requested_due" -le "$now" ]; then
    requested_due=$((now + 60))
  fi
  rounded=$(( (requested_due + 59) / 60 * 60 ))

  mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"

  python3 - "$WAKE_PLIST" "$WAKE_LABEL" "$RUNNER" "$ROOT" "$LOG" "$rounded" <<'PY'
import datetime as dt
import plistlib
import sys

plist_path, label, runner, working_dir, log_path, epoch = sys.argv[1:7]
when = dt.datetime.fromtimestamp(int(epoch)).astimezone()
data = {
    "Label": label,
    "ProgramArguments": ["/bin/bash", runner, "wakeup"],
    "RunAtLoad": True,
    "StartCalendarInterval": {
        "Month": when.month,
        "Day": when.day,
        "Hour": when.hour,
        "Minute": when.minute,
    },
    "WorkingDirectory": working_dir,
    "StandardOutPath": log_path,
    "StandardErrorPath": log_path,
    "ProcessType": "Background",
}
with open(plist_path, "wb") as f:
    plistlib.dump(data, f, fmt=plistlib.FMT_XML)
PY

  chmod 644 "$WAKE_PLIST"
  bootout "$WAKE_LABEL"
  launchctl bootstrap "$DOMAIN" "$WAKE_PLIST"
  launchctl enable "$DOMAIN/$WAKE_LABEL" >/dev/null 2>&1 || true
}

write_retry_plist() {
  local minute
  minute="$(date '+%M')"
  # Strip a possible leading zero before handing the value to Python/int.
  minute="$((10#$minute))"

  python3 - "$RETRY_PLIST" "$RETRY_LABEL" "$RUNNER" "$ROOT" "$LOG" "$minute" <<'PY'
import plistlib
import sys

plist_path, label, runner, working_dir, log_path, minute = sys.argv[1:7]
data = {
    "Label": label,
    "ProgramArguments": ["/bin/bash", runner, "retry"],
    "RunAtLoad": True,
    "StartCalendarInterval": {"Minute": int(minute)},
    "WorkingDirectory": working_dir,
    "StandardOutPath": log_path,
    "StandardErrorPath": log_path,
    "ProcessType": "Background",
}
with open(plist_path, "wb") as f:
    plistlib.dump(data, f, fmt=plistlib.FMT_XML)
PY
  chmod 600 "$RETRY_PLIST"
}

activate_retry() {
  mkdir -p "$HOME/Library/Logs"
  chmod +x "$RUNNER" 2>/dev/null || true
  write_retry_plist

  if loaded "$RETRY_LABEL"; then
    launchctl kickstart "$DOMAIN/$RETRY_LABEL" >/dev/null 2>&1 || true
    return 0
  fi

  launchctl bootstrap "$DOMAIN" "$RETRY_PLIST"
  launchctl enable "$DOMAIN/$RETRY_LABEL" >/dev/null 2>&1 || true
  launchctl kickstart "$DOMAIN/$RETRY_LABEL" >/dev/null 2>&1 || true
}

reconcile_schedule() {
  local device expiry now due mode
  device="$(target_device)"
  if [ -z "$device" ]; then
    echo "No smart auto-refresh target iPhone is configured." >&2
    return 75
  fi

  now="$(date +%s)"
  expiry="$(read_install_receipt_expiration_epoch "$device" 2>/dev/null || true)"

  if [ -n "$expiry" ]; then
    due=$((expiry - AUTO_REFRESH_WINDOW_SECONDS))
  else
    due="$now"
  fi

  # Program the future wake-up FIRST. If reconcile is running inside the retry
  # worker, unloading the retry label below may terminate that worker.
  write_wake_plist "$due"

  if [ -n "$expiry" ] && [ "$due" -gt "$now" ]; then
    mode="quiet"
    write_schedule_state "$device" "$expiry" "$due" "$mode"
    bootout "$RETRY_LABEL"
  else
    mode="hourly-retry"
    write_schedule_state "$device" "$expiry" "$due" "$mode"
    activate_retry
  fi
}

show_status() {
  local device expiry now due rem mode

  echo
  echo "===================================================="
  echo "      WeChat 2 — Smart Auto-Refresh Status"
  echo "===================================================="
  echo

  if [ -f "$WAKE_PLIST" ]; then
    echo "Schedule installed : yes"
  else
    echo "Schedule installed : no"
  fi

  if loaded "$WAKE_LABEL"; then
    echo "Wake agent loaded   : yes"
  else
    echo "Wake agent loaded   : no"
  fi

  if loaded "$RETRY_LABEL"; then
    echo "Retry agent loaded  : yes"
  else
    echo "Retry agent loaded  : no"
  fi

  if [ -f "$LEGACY_PLIST" ] || loaded "$LEGACY_LABEL"; then
    echo "Legacy hourly agent : PRESENT (run install schedule again to migrate)"
  else
    echo "Legacy hourly agent : no"
  fi

  device="$(target_device)"
  [ -n "$device" ] && echo "Target iPhone ID    : $device"

  expiry=""
  if [ -n "$device" ]; then
    expiry="$(read_install_receipt_expiration_epoch "$device" 2>/dev/null || true)"
  fi

  now="$(date +%s)"
  if [ -n "$expiry" ]; then
    due=$((expiry - AUTO_REFRESH_WINDOW_SECONDS))
    rem=$((expiry - now))
    echo "Verified expiry     : $(date -r "$expiry" '+%Y-%m-%d %H:%M:%S %Z')"
    echo "Renewal window      : $(date -r "$due" '+%Y-%m-%d %H:%M:%S %Z')"

    if [ "$due" -gt "$now" ]; then
      mode="quiet — no hourly worker"
    elif [ "$rem" -gt 0 ]; then
      mode="renewal window — hourly retry"
    else
      mode="expired — hourly retry"
    fi
    echo "Current mode        : $mode"
  else
    echo "Verified expiry     : unknown (no successful-install receipt)"
    echo "Current mode        : hourly retry until one successful install is verified"
  fi

  echo "Install receipt     : $INSTALL_RECEIPT_FILE"
  echo "Log file            : $LOG"
  echo
}

install_schedule() {
  local device expiry

  require_xcode
  ensure_bootstrap_project
  ensure_state_dir
  recover_pending_profile_cache_transactions >/dev/null 2>&1 || true

  device="$(read_last_device_id 2>/dev/null || true)"
  if [ -n "$device" ]; then
    echo "Using last successfully installed iPhone:"
    echo "  $device"
  else
    pick_device
    device="$DEVICE_ID"
  fi

  save_autorefresh_device_id "$device"

  # Remove the previous single hourly agent before installing the two-stage one.
  bootout "$LEGACY_LABEL"
  rm -f "$LEGACY_PLIST"

  expiry="$(read_install_receipt_expiration_epoch "$device" 2>/dev/null || true)"
  if [ -z "$expiry" ]; then
    echo
    echo "No verified successful-install receipt exists for this iPhone."

    if list_physical_iphones | grep -Fq "($device)"; then
      echo "The target iPhone is online. One install/refresh will run now so the"
      echo "scheduler starts from the actual profiles that were successfully installed."
      echo
      WECHAT2_DEVICE_ID="$device" WECHAT2_AUTOREFRESH_CONTEXT=1 "$ROOT/install_wechat2.command"
    else
      echo "⚠️  The target iPhone is offline."
      echo "The retry worker will remain active until a successful install creates"
      echo "a verified all-bundle receipt."
      echo
    fi
  fi

  reconcile_schedule

  echo
  echo "✅ Smart auto-refresh schedule installed."
  echo
  echo "Behavior:"
  echo "  • Quiet phase: no hourly LaunchAgent is loaded."
  echo "  • A wake agent is scheduled for verified expiry minus $((AUTO_REFRESH_WINDOW_SECONDS / 3600))h."
  echo "  • In the renewal window, an hourly retry worker is enabled."
  echo "  • Automatic renewal must produce a genuinely later ExpirationDate."
  echo "  • Matching old provisioning-cache entries are transactionally backed up first."
  echo "  • The signed app validates every embedded .app/.appex profile before install."
  echo "  • Expiry state is committed only after devicectl reports a successful install."
  echo
  show_status
}

uninstall_schedule() {
  bootout "$WAKE_LABEL"
  bootout "$RETRY_LABEL"
  bootout "$LEGACY_LABEL"

  rm -f "$WAKE_PLIST" "$RETRY_PLIST" "$LEGACY_PLIST"
  rm -f "$SCHEDULE_STATE" "$AUTO_REFRESH_DEVICE_FILE"

  echo
  echo "✅ Smart auto-refresh schedule uninstalled."
  echo "WeChat 2, install receipt/history, and profile-backup history were left untouched."
  echo
}

case "${1:-}" in
  install)
    install_schedule
    ;;
  uninstall)
    uninstall_schedule
    ;;
  status)
    show_status
    ;;
  reconcile)
    reconcile_schedule
    ;;
  activate-retry)
    activate_retry
    ;;
  "")
    echo
    echo "WeChat 2 Smart Auto-Refresh"
    echo
    echo "  1) Install schedule"
    echo "  2) Uninstall schedule"
    echo "  3) Status"
    echo "  0) Exit"
    echo
    read -r -p "Choose: " c
    case "$c" in
      1) install_schedule ;;
      2) uninstall_schedule ;;
      3) show_status ;;
      0) exit 0 ;;
      *) echo "Invalid choice."; exit 1 ;;
    esac
    ;;
  *)
    echo "Usage: $0 [install|uninstall|status|reconcile|activate-retry]"
    exit 2
    ;;
esac
