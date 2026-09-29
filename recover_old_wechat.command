#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$DIR/lib/common.sh"

load_config

# Dedicated recovery defaults for the older clone. These can be overridden
# without touching config.env or the normal WeChat 2 scheduler.
RECOVERY_BUNDLE_ID="${WECHAT2_RECOVERY_BUNDLE_ID:-com.kj.wechat2}"
RECOVERY_TEAM_ID="${WECHAT2_RECOVERY_TEAM_ID:-468U2JDYD3}"
RECOVERY_APP_NAME="${WECHAT2_RECOVERY_APP_NAME:-WeChat}"
RECOVERY_BACKUP_DIR="${WECHAT2_RECOVERY_BACKUP_DIR:-$HOME/Desktop/WeChat-old-8.0.78-backup}"

# Keep every recovery artifact/state file separate from the normal clone.
RECOVERY_ROOT="$ROOT/.recovery-old"
GENERATED="$RECOVERY_ROOT/.generated"
PROJECT_DIR="$GENERATED/WeChatCloneProfile"
PROJECT="$PROJECT_DIR/WeChatCloneProfile.xcodeproj"
BUILD_DIR="$RECOVERY_ROOT/.build"
WORK_DIR="$RECOVERY_ROOT/.work"
OUTPUT_DIR="$RECOVERY_ROOT/Output"
STATE_DIR="$RECOVERY_ROOT/.state"
PROFILE_EXPIRY_FILE="$STATE_DIR/profile_expiration_epoch"
PROFILE_EXPIRY_ISO_FILE="$STATE_DIR/profile_expiration_iso"
LAST_DEVICE_FILE="$STATE_DIR/last_device_id"
AUTO_REFRESH_DEVICE_FILE="$STATE_DIR/autorefresh_device_id"
INSTALL_RECEIPT_FILE="$STATE_DIR/recovery_install_receipt.json"
AUTOREFRESH_MANIFEST_FILE="$WORK_DIR/install-profile-manifest.json"

BUNDLE_ID="$RECOVERY_BUNDLE_ID"
TEAM_ID="$RECOVERY_TEAM_ID"
APP_NAME="$RECOVERY_APP_NAME"

echo
echo "===================================================="
echo "     Recover old WeChat clone without deleting data"
echo "===================================================="
echo
echo "Target Bundle ID : $BUNDLE_ID"
echo "Required Team ID : $TEAM_ID"
echo "Backup directory : $RECOVERY_BACKUP_DIR"
echo

[ -d "$RECOVERY_BACKUP_DIR/Documents" ] || die "Backup Documents folder is missing: $RECOVERY_BACKUP_DIR/Documents"
[ -d "$RECOVERY_BACKUP_DIR/Library" ] || die "Backup Library folder is missing: $RECOVERY_BACKUP_DIR/Library"

DOC_KB="$(du -sk "$RECOVERY_BACKUP_DIR/Documents" 2>/dev/null | awk '{print $1}')"
LIB_KB="$(du -sk "$RECOVERY_BACKUP_DIR/Library" 2>/dev/null | awk '{print $1}')"
DOC_KB="${DOC_KB:-0}"
LIB_KB="${LIB_KB:-0}"

[ "$DOC_KB" -gt 1024 ] || die "Documents backup appears unexpectedly small; refusing recovery update."
[ "$LIB_KB" -gt 1024 ] || die "Library backup appears unexpectedly small; refusing recovery update."

echo "✅ Backup check passed:"
du -sh "$RECOVERY_BACKUP_DIR/Documents" "$RECOVERY_BACKUP_DIR/Library"

require_xcode
ensure_bootstrap_project
pick_device

APPS_LOG="$STATE_DIR/apps-before.txt"
mkdir -p "$STATE_DIR"
xcrun devicectl device info apps --device "$DEVICE_ID" > "$APPS_LOG"

OLD_LINE="$(grep -F "$BUNDLE_ID" "$APPS_LOG" | head -1 || true)"
[ -n "$OLD_LINE" ] || die "The old clone $BUNDLE_ID is not installed on the selected iPhone. In-place recovery requires the existing app to remain installed."

echo
echo "✅ Existing old clone found:"
echo "   $OLD_LINE"

check_ipa_cryptid

SOURCE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$CHECK_PLIST" 2>/dev/null || echo unknown)"
SOURCE_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$CHECK_PLIST" 2>/dev/null || echo unknown)"

echo
echo "Recovery plan:"
echo "  Existing app : $OLD_LINE"
echo "  Source IPA   : version $SOURCE_VERSION (build $SOURCE_BUILD)"
echo "  New Bundle ID remains exactly: $BUNDLE_ID"
echo "  Signing Team remains exactly : $TEAM_ID"
echo "  The old app will NOT be uninstalled."
echo "  The new IPA will be installed over the existing app so iOS can retain"
echo "  the existing app data container."
echo
echo "The normal clone ($ROOT config.env), its scheduler, and its install receipt"
echo "will not be modified by this recovery workflow."
echo

read -r -p "Type RECOVER to continue: " CONFIRM
[ "$CONFIRM" = "RECOVER" ] || {
  echo "Cancelled. Nothing was installed."
  exit 0
}

prepare_team_interactively_if_needed
build_bootstrap_profile
find_signing_identity

mkdir -p "$WORK_DIR" "$OUTPUT_DIR"
rm -rf "$WORK_DIR/sign"
mkdir -p "$WORK_DIR/sign"

note "Extracting source IPA..."
unzip -q "$IPA" -d "$WORK_DIR/sign"

APP="$(find "$WORK_DIR/sign/Payload" -maxdepth 1 -type d -name '*.app' | head -1)"
[ -n "$APP" ] || die "No Payload/*.app was found."
PLIST="$APP/Info.plist"

OLD_SOURCE_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")"
note "Changing source Bundle ID: $OLD_SOURCE_BUNDLE_ID -> $BUNDLE_ID"

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
  note "Removing embedded extensions / Watch / AppClips for recovery compatibility..."
  rm -rf "$APP/PlugIns" "$APP/Watch" "$APP/AppClips" "$APP/Extensions"
else
  warn "Embedded extensions remain enabled and must have their own valid profiles."
fi

rewrite_plist_string_refs "$APP" "$OLD_SOURCE_BUNDLE_ID" "$BUNDLE_ID"

note "Removing old signatures and App Store metadata..."
find "$APP" -type d -name '_CodeSignature' -prune -exec rm -rf {} + 2>/dev/null || true
rm -f "$APP/embedded.mobileprovision"
rm -rf "$APP/SC_Info"
xattr -cr "$APP" >/dev/null 2>&1 || true

cp "$PROFILE" "$APP/embedded.mobileprovision"

PROFILE_APP_ID="$(/usr/libexec/PlistBuddy -c 'Print :application-identifier' "$ENTITLEMENTS" 2>/dev/null || true)"
[ -n "$PROFILE_APP_ID" ] && note "Recovery profile application-identifier: $PROFILE_APP_ID"

sign_nested_code "$APP"

note "Signing recovered app..."
codesign \
  --force \
  --sign "$IDENTITY_HASH" \
  --entitlements "$ENTITLEMENTS" \
  --timestamp=none \
  "$APP"

verify_signed_app "$APP"
prepare_install_profile_manifest "$APP" "$DEVICE_ID" "$DISCOVERED_TEAM"

SIGNED_IPA="$OUTPUT_DIR/WeChat-old-recovery-signed.ipa"
rm -f "$SIGNED_IPA"
(
  cd "$WORK_DIR/sign"
  /usr/bin/zip -qry "$SIGNED_IPA" Payload
)
ok "Recovery IPA exported: $SIGNED_IPA"

echo
note "Installing IN PLACE over $BUNDLE_ID — no uninstall..."
install_app_with_retry "$DEVICE_ID" "$APP"

# Record only inside .recovery-old. Do not touch the normal clone's receipt/state.
commit_successful_install_receipt "$APP" "$DEVICE_ID" "$DISCOVERED_TEAM"

echo
echo "===================================================="
echo "✅ Old WeChat clone updated in place"
echo "===================================================="
echo "Bundle ID : $BUNDLE_ID"
echo "Version   : $SOURCE_VERSION"
echo
echo "The old data container was not intentionally deleted."
echo "Do NOT uninstall the app if WeChat needs time to migrate its local database."
echo
echo "Open it manually, or run:"
echo
echo "xcrun devicectl device process launch \\"
echo "  --device $DEVICE_ID \\"
echo "  $BUNDLE_ID"
echo
