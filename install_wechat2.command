#!/bin/bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$DIR/lib/common.sh"

load_config

echo
echo "===================================================="
echo "          WeChat 2 — Sign & Install"
echo "===================================================="
echo

require_xcode
ensure_bootstrap_project
pick_device
prepare_team_interactively_if_needed
check_ipa_cryptid
build_bootstrap_profile
find_signing_identity

mkdir -p "$WORK_DIR" "$OUTPUT_DIR"
rm -rf "$WORK_DIR/sign"
mkdir -p "$WORK_DIR/sign"

note "Extracting IPA..."
unzip -q "$IPA" -d "$WORK_DIR/sign"

APP="$(find "$WORK_DIR/sign/Payload" -maxdepth 1 -type d -name '*.app' | head -1)"
[ -n "$APP" ] || die "No Payload/*.app was found."
PLIST="$APP/Info.plist"

OLD_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")"
note "Changing Bundle ID: $OLD_BUNDLE_ID -> $BUNDLE_ID"

/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$PLIST"

if /usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$PLIST" >/dev/null 2>&1; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName '$APP_NAME'" "$PLIST"
else
  /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string '$APP_NAME'" "$PLIST"
fi

if /usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$PLIST" >/dev/null 2>&1; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleName '$APP_NAME'" "$PLIST"
fi

if [ "$REMOVE_EXTENSIONS" = "1" ]; then
  note "Removing embedded extensions / Watch / AppClips for first-pass compatibility..."
  rm -rf "$APP/PlugIns" "$APP/Watch" "$APP/AppClips" "$APP/Extensions"
else
  warn "Embedded extensions remain enabled and may need separate App IDs/profiles."
fi

rewrite_plist_string_refs "$APP" "$OLD_BUNDLE_ID" "$BUNDLE_ID"

note "Removing old signatures and App Store metadata..."
find "$APP" -type d -name '_CodeSignature' -prune -exec rm -rf {} + 2>/dev/null || true
rm -f "$APP/embedded.mobileprovision"
rm -rf "$APP/SC_Info"
xattr -cr "$APP" >/dev/null 2>&1 || true

cp "$PROFILE" "$APP/embedded.mobileprovision"

PROFILE_APP_ID="$(/usr/libexec/PlistBuddy -c 'Print :application-identifier' "$ENTITLEMENTS" 2>/dev/null || true)"
[ -n "$PROFILE_APP_ID" ] && note "Profile application-identifier: $PROFILE_APP_ID"

sign_nested_code "$APP"

note "Signing main app..."
codesign \
  --force \
  --sign "$IDENTITY_HASH" \
  --entitlements "$ENTITLEMENTS" \
  --timestamp=none \
  "$APP"

verify_signed_app "$APP"

if [ "$EXPORT_SIGNED_IPA" = "1" ]; then
  SIGNED_IPA="$OUTPUT_DIR/WeChat2-signed.ipa"
  rm -f "$SIGNED_IPA"
  (
    cd "$WORK_DIR/sign"
    /usr/bin/zip -qry "$SIGNED_IPA" Payload
  )
  ok "Signed IPA exported: $SIGNED_IPA"
fi

echo
note "Installing on iPhone..."
install_app_with_retry "$DEVICE_ID" "$APP"

record_profile_expiration_state "$PROFILE_PLIST"
save_last_device_id "$DEVICE_ID"

echo
echo "===================================================="
echo "✅ WeChat 2 installed"
echo "===================================================="
echo "Name:      $APP_NAME"
echo "Bundle ID: $BUNDLE_ID"
echo
echo "If iOS requests Developer Mode/trust, complete it on the phone."
