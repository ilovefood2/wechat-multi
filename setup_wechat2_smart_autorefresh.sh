#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/lib/common.sh"

load_config

LABEL="com.ilovefood2.wechat2.smart-autorefresh"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/WeChat2SmartAutoRefresh.log"
RUNNER="$ROOT/lib/smart_autorefresh.sh"
DOMAIN="gui/$(id -u)"

loaded() {
  launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1
}

show_status() {
  recover_profile_expiration_state >/dev/null 2>&1 || true

  echo
  echo "===================================================="
  echo "      WeChat 2 — Smart Auto-Refresh Status"
  echo "===================================================="
  echo

  if [ -f "$PLIST" ]; then
    echo "Schedule installed : yes"
  else
    echo "Schedule installed : no"
  fi

  if loaded; then
    echo "LaunchAgent loaded : yes"
  else
    echo "LaunchAgent loaded : no"
  fi

  TARGET="$(read_autorefresh_device_id 2>/dev/null || true)"
  [ -n "$TARGET" ] && echo "Target iPhone ID    : $TARGET"

  if EXPIRY="$(read_profile_expiration_epoch 2>/dev/null)"; then
    HUMAN="$(profile_expiration_human 2>/dev/null || echo "$EXPIRY")"
    NOW="$(date +%s)"
    REM=$((EXPIRY - NOW))
    echo "Profile expires     : $HUMAN"
    if [ "$REM" -gt 86400 ]; then
      echo "Current mode        : idle gate only (no signing retry until final 24h)"
    elif [ "$REM" -gt 0 ]; then
      echo "Current mode        : hourly refresh attempts enabled (inside final 24h)"
    else
      echo "Current mode        : expired; hourly refresh attempts enabled"
    fi
  else
    echo "Profile expires     : unknown"
    echo "Current mode        : hourly refresh attempts until a successful install records expiry"
  fi

  echo "Log file            : $LOG"
  echo
}

install_schedule() {
  require_xcode
  ensure_bootstrap_project
  ensure_state_dir

  DEVICE_ID="$(read_last_device_id 2>/dev/null || true)"
  if [ -n "$DEVICE_ID" ]; then
    echo "Using last successfully installed iPhone:"
    echo "  $DEVICE_ID"
  else
    pick_device
  fi

  save_autorefresh_device_id "$DEVICE_ID"

  recover_profile_expiration_state >/dev/null 2>&1 || true

  if ! read_profile_expiration_epoch >/dev/null 2>&1; then
    echo
    echo "No existing profile expiration could be recovered from local install artifacts."

    if list_physical_iphones | grep -Fq "($DEVICE_ID)"; then
      echo "The target iPhone is online, so one refresh will run now to establish"
      echo "an accurate provisioning expiration before the hourly schedule starts."
      echo
      WECHAT2_DEVICE_ID="$DEVICE_ID" "$ROOT/install_wechat2.command"
      recover_profile_expiration_state >/dev/null 2>&1 || true
    else
      echo "⚠️  The target iPhone is offline. The schedule will still be installed."
      echo "Until the first successful refresh records the real expiration, the"
      echo "hourly job will attempt a refresh each hour so an unknown expiry cannot"
      echo "silently lapse."
      echo
    fi
  fi

  mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"

  python3 - "$PLIST" "$LABEL" "$RUNNER" "$ROOT" "$LOG" <<'PY'
import plistlib
import sys

plist_path, label, runner, working_dir, log_path = sys.argv[1:6]
data = {
    "Label": label,
    "ProgramArguments": ["/bin/bash", runner],
    "RunAtLoad": True,
    "StartInterval": 3600,
    "WorkingDirectory": working_dir,
    "StandardOutPath": log_path,
    "StandardErrorPath": log_path,
    "ProcessType": "Background",
}
with open(plist_path, "wb") as f:
    plistlib.dump(data, f, fmt=plistlib.FMT_XML)
PY

  chmod 644 "$PLIST"
  chmod +x "$RUNNER"

  launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
  launchctl bootstrap "$DOMAIN" "$PLIST"
  launchctl enable "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
  launchctl kickstart -k "$DOMAIN/$LABEL" >/dev/null 2>&1 || true

  echo
  echo "✅ Smart auto-refresh schedule installed."
  echo
  echo "Behavior:"
  echo "  • launchd performs a lightweight local expiry check once per hour."
  echo "  • Until the final 24h: no Xcode signing/device retry is performed."
  echo "  • Final 24h: it attempts refresh once per hour."
  echo "  • If the iPhone/Mac/network is unavailable, the next hourly run retries."
  echo "  • After a successful refresh, the new expiry is recorded and retries go idle again."
  echo
  show_status
}

uninstall_schedule() {
  launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
  rm -f "$PLIST" "$AUTO_REFRESH_DEVICE_FILE"
  echo
  echo "✅ Smart auto-refresh schedule uninstalled."
  echo "Existing WeChat 2 installation and expiry history were left untouched."
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
    echo "Usage: $0 [install|uninstall|status]"
    exit 2
    ;;
esac
