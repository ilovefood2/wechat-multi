#!/bin/bash
set -euo pipefail

SOURCE_APP="/Applications/WeChat.app"
CLONE_APP="/Applications/WeChat2.app"
APP_NAME="WeChat 2"
BUNDLE_ID="com.kj.wechat2"
APP_STORE_ID="836500024"
STAMP="$(date '+%Y%m%d_%H%M%S')"

ok()   { echo "✅ $*"; }
note() { echo "ℹ️  $*"; }
warn() { echo "⚠️  $*"; }
die()  { echo; echo "❌ $*" >&2; exit 1; }

echo
echo "===================================================="
echo "       WeChat 2 — macOS One-Click Installer"
echo "===================================================="
echo

if [ ! -d "$SOURCE_APP" ]; then
  warn "Official WeChat is not installed in /Applications."
  echo "Opening the Mac App Store page for WeChat..."
  open "macappstore://itunes.apple.com/app/id${APP_STORE_ID}" || true
  echo
  echo "Install official WeChat, then run this installer again."
  exit 0
fi

PLIST_SRC="$SOURCE_APP/Contents/Info.plist"
[ -f "$PLIST_SRC" ] || die "Invalid WeChat.app: missing Contents/Info.plist"

ORIGINAL_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST_SRC")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST_SRC" 2>/dev/null || echo unknown)"

ok "Found WeChat $VERSION ($ORIGINAL_ID)"

echo
note "Administrator permission is required to write to /Applications."
sudo -v

if [ -d "$CLONE_APP" ]; then
  BACKUP="/Applications/WeChat2.backup.${STAMP}.app"
  note "Backing up existing WeChat2.app to $BACKUP"
  sudo mv "$CLONE_APP" "$BACKUP"
fi

note "Cloning official WeChat..."
sudo /usr/bin/ditto "$SOURCE_APP" "$CLONE_APP"

[ -d "$CLONE_APP/Contents" ] || die "Clone failed: Contents directory is missing."

# Guard against the copy mistake that creates WeChat2.app/WeChat.app.
if [ -e "$CLONE_APP/WeChat.app" ]; then
  warn "Removing invalid nested WeChat.app from clone root."
  sudo rm -rf "$CLONE_APP/WeChat.app"
fi

PLIST="$CLONE_APP/Contents/Info.plist"

note "Changing Bundle ID and display name..."
sudo /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$PLIST"

if /usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$PLIST" >/dev/null 2>&1; then
  sudo /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName '$APP_NAME'" "$PLIST"
else
  sudo /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string '$APP_NAME'" "$PLIST"
fi

if /usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$PLIST" >/dev/null 2>&1; then
  sudo /usr/libexec/PlistBuddy -c "Set :CFBundleName '$APP_NAME'" "$PLIST"
fi

# Update plain-string references to the original app ID in plist files only.
note "Updating plist references to the cloned Bundle ID..."
while IFS= read -r -d '' p; do
  sudo plutil -convert xml1 "$p" >/dev/null 2>&1 || continue
  if sudo grep -qF "$ORIGINAL_ID" "$p" 2>/dev/null; then
    sudo /usr/bin/python3 - "$p" "$ORIGINAL_ID" "$BUNDLE_ID" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
old, new = sys.argv[2], sys.argv[3]
s = p.read_text(errors="ignore")
p.write_text(s.replace(old, new))
PY
  fi
done < <(find "$CLONE_APP/Contents" -type f -name '*.plist' -print0)

note "Cleaning metadata and old signatures..."
sudo find "$CLONE_APP" -name '.DS_Store' -delete 2>/dev/null || true
sudo find "$CLONE_APP" -name '._*' -delete 2>/dev/null || true
sudo xattr -cr "$CLONE_APP"
sudo find "$CLONE_APP" -type d -name '_CodeSignature' -prune -exec rm -rf {} + 2>/dev/null || true

ROOT_EXTRA="$(find "$CLONE_APP" -maxdepth 1 -mindepth 1 ! -name Contents -print)"
[ -z "$ROOT_EXTRA" ] || die "Unexpected item(s) in app bundle root: $ROOT_EXTRA"

note "Ad-hoc signing WeChat 2..."
sudo /usr/bin/codesign --force --deep --sign - "$CLONE_APP"

note "Verifying code signature..."
/usr/bin/codesign --verify --deep --strict --verbose=2 "$CLONE_APP"
ok "Signature verified."

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
  "$LSREGISTER" -f "$CLONE_APP" >/dev/null 2>&1 || true
fi

FINAL_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")"

echo
echo "===================================================="
echo "✅ WeChat 2 ready"
echo "===================================================="
echo "Original:  $SOURCE_APP"
echo "Clone:     $CLONE_APP"
echo "Bundle ID: $FINAL_ID"
echo

open -n "$CLONE_APP"
