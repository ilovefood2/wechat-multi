#!/bin/bash
set -u -o pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$DIR/lib/common.sh"

load_config

echo
echo "===================================================="
echo "        WeChat 2 — Paired Device Information"
echo "===================================================="
echo

if [ ! -d "/Applications/Xcode.app" ]; then
  warn "Full Xcode is not installed at /Applications/Xcode.app."
  exit 2
fi
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

echo "Xcode:"
xcodebuild -version 2>/dev/null | sed 's/^/  /' || echo "  Xcode command-line tools are not ready."
echo

echo "CoreDevice paired / known devices:"
echo "----------------------------------------------------"
if ! xcrun devicectl list devices 2>&1; then
  warn "devicectl could not list paired devices."
fi
echo

LAST_ID="$(read_last_device_id 2>/dev/null || true)"
AUTO_ID="$(read_autorefresh_device_id 2>/dev/null || true)"

echo "Saved deployment targets:"
echo "----------------------------------------------------"
if [ -n "$LAST_ID" ]; then
  echo "  Last successful install : $LAST_ID"
else
  echo "  Last successful install : none recorded"
fi
if [ -n "$AUTO_ID" ]; then
  echo "  Auto-refresh target     : $AUTO_ID"
else
  echo "  Auto-refresh target     : none recorded"
fi
echo "  Configured clone        : $BUNDLE_ID"
echo

VISIBLE="$(list_physical_iphones)"
if [ -z "$VISIBLE" ]; then
  echo "Currently visible physical iPhones:"
  echo "----------------------------------------------------"
  echo "  None."
  echo
  echo "A device can still appear in the CoreDevice paired list above while"
  echo "being offline, locked, disconnected, or unavailable to Xcode."
  exit 0
fi

echo "Currently visible physical iPhones:"
echo "----------------------------------------------------"
printf '%s\n' "$VISIBLE" | nl -w2 -s') '
echo

while IFS= read -r DEVICE_LINE; do
  [ -n "$DEVICE_LINE" ] || continue

  DEVICE_ID="$(printf '%s\n' "$DEVICE_LINE" | sed -E 's/.*\(([[:alnum:]-]{20,})\)$/\1/')"
  [ -n "$DEVICE_ID" ] || continue

  echo "===================================================="
  echo "$DEVICE_LINE"

  TAGS=""
  [ "$DEVICE_ID" = "$LAST_ID" ] && TAGS="${TAGS} last-install"
  [ "$DEVICE_ID" = "$AUTO_ID" ] && TAGS="${TAGS} auto-refresh"
  if [ -n "$TAGS" ]; then
    echo "Role(s):${TAGS}"
  fi
  echo "Identifier: $DEVICE_ID"
  echo

  echo "CoreDevice details:"
  DETAILS="$(xcrun devicectl device info details --device "$DEVICE_ID" --timeout 10 2>&1)"
  DETAILS_RC=$?
  if [ "$DETAILS_RC" -eq 0 ]; then
    FILTERED="$(printf '%s\n' "$DETAILS" | grep -Ei       '(^|[[:space:]])(name|identifier|state|connection|transport|developer.?mode|product.?type|hardware|marketing.?name|operating.?system|os.?version|paired|tunnel)[[:space:]]*[:=]'       | head -40 || true)"
    if [ -n "$FILTERED" ]; then
      printf '%s\n' "$FILTERED" | sed 's/^/  /'
    else
      # Output format changes across Xcode versions; show the first useful lines
      # instead of pretending the parser found structured fields.
      printf '%s\n' "$DETAILS" | head -25 | sed 's/^/  /'
    fi
  else
    echo "  Unable to query details:"
    printf '%s\n' "$DETAILS" | tail -8 | sed 's/^/  /'
  fi
  echo

  echo "Xcode run destination:"
  if [ -f "$PROJECT/project.pbxproj" ]; then
    DEST="$(show_destinations | grep -F "id:$DEVICE_ID" | head -1 || true)"
    if [ -n "$DEST" ]; then
      echo "  READY"
      echo "  $DEST"
    else
      echo "  Not currently listed as a usable destination for the bootstrap project."
    fi
  else
    echo "  Bootstrap project has not been generated on this Mac yet."
  fi
  echo

  echo "WeChat developer installs visible to CoreDevice:"
  APPS="$(xcrun devicectl device info apps --device "$DEVICE_ID" --timeout 15 2>&1)"
  APPS_RC=$?
  if [ "$APPS_RC" -eq 0 ]; then
    MATCHES="$(printf '%s\n' "$APPS" | grep -Ei 'wechat|weixin|com\.tencent\.xin|com\.kj\.wechat|com\.kelvin\.wechat' || true)"
    if [ -n "$MATCHES" ]; then
      printf '%s\n' "$MATCHES" | sed 's/^/  /'
    else
      echo "  No WeChat developer installs were returned."
    fi
  else
    echo "  Unable to query installed apps:"
    printf '%s\n' "$APPS" | tail -8 | sed 's/^/  /'
  fi
  echo

  if RECEIPT_EXPIRY="$(read_install_receipt_expiration_epoch "$DEVICE_ID" 2>/dev/null)"; then
    NOW="$(date +%s)"
    REM=$((RECEIPT_EXPIRY - NOW))
    echo "Configured clone receipt:"
    echo "  Verified expiry : $(date -r "$RECEIPT_EXPIRY" '+%Y-%m-%d %H:%M:%S %Z')"
    if [ "$REM" -gt 0 ]; then
      echo "  Time remaining  : $((REM / 86400))d $(((REM % 86400) / 3600))h"
    else
      echo "  Status          : expired"
    fi
    echo
  fi

done <<< "$VISIBLE"

echo "===================================================="
echo "Apple Development signing identities on this Mac:"
echo "----------------------------------------------------"
IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null | grep '"Apple Development:' || true)"
if [ -n "$IDENTITIES" ]; then
  printf '%s\n' "$IDENTITIES" | sed 's/^/  /'
else
  echo "  None found."
fi
echo
