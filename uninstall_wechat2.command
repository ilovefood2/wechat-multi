#!/bin/bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$DIR/lib/common.sh"
load_config
require_xcode
pick_device

echo
echo "This removes only:"
echo "  $APP_NAME ($BUNDLE_ID)"
echo
read -r -p "Continue? [y/N] " ans
case "$ans" in
  y|Y|yes|YES) ;;
  *) echo "Cancelled."; exit 0 ;;
esac

xcrun devicectl device uninstall app --device "$DEVICE_ID" "$BUNDLE_ID"
ok "Uninstalled $APP_NAME"
