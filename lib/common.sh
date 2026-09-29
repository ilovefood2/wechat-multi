#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$ROOT/config.env"
GENERATED="$ROOT/.generated"
PROJECT_DIR="$GENERATED/WeChatCloneProfile"
PROJECT="$PROJECT_DIR/WeChatCloneProfile.xcodeproj"
SCHEME="WeChatCloneProfile"
BUILD_DIR="$ROOT/.build"
WORK_DIR="$ROOT/.work"
OUTPUT_DIR="$ROOT/Output"
STATE_DIR="$ROOT/.state"
PROFILE_EXPIRY_FILE="$STATE_DIR/profile_expiration_epoch"
PROFILE_EXPIRY_ISO_FILE="$STATE_DIR/profile_expiration_iso"
LAST_DEVICE_FILE="$STATE_DIR/last_device_id"
AUTO_REFRESH_DEVICE_FILE="$STATE_DIR/autorefresh_device_id"

die() {
  echo
  echo "❌ $*" >&2
  exit 1
}

ok()   { echo "✅ $*"; }
note() { echo "ℹ️  $*"; }
warn() { echo "⚠️  $*"; }

load_config() {
  [ -f "$CONFIG" ] || die "Missing config.env"
  # shellcheck disable=SC1090
  source "$CONFIG"

  : "${APP_NAME:?APP_NAME missing}"
  : "${BUNDLE_ID:?BUNDLE_ID missing}"
  : "${TEAM_ID:=}"
  : "${IPA_RELATIVE_PATH:?IPA_RELATIVE_PATH missing}"
  : "${REMOVE_EXTENSIONS:=1}"
  : "${EXPORT_SIGNED_IPA:=1}"

  IPA="$ROOT/$IPA_RELATIVE_PATH"
}

require_xcode() {
  [ -d "/Applications/Xcode.app" ] || {
    echo
    echo "Xcode is not installed."
    echo "Install the full Xcode app from the Mac App Store, open it once,"
    echo "finish first-run setup, and sign into your Apple Account under:"
    echo "  Xcode > Settings > Accounts"
    exit 2
  }

  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

  if ! xcodebuild -version >/dev/null 2>&1; then
    die "Xcode is installed but not ready. Open Xcode once and complete first-run setup."
  fi
}

create_bootstrap_project() {
  mkdir -p "$PROJECT_DIR/WeChatCloneProfile"
  mkdir -p "$PROJECT/xcshareddata/xcschemes"

  cat > "$PROJECT_DIR/WeChatCloneProfile/WeChatCloneProfileApp.swift" <<'SWIFT'
import SwiftUI

@main
struct WeChatCloneProfileApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
SWIFT

  cat > "$PROJECT_DIR/WeChatCloneProfile/ContentView.swift" <<'SWIFT'
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 50))
            Text("WeChat 2 Provisioning Test")
                .font(.headline)
            Text("If this runs on the iPhone, Apple development signing is ready.")
                .multilineTextAlignment(.center)
                .padding()
        }
    }
}
SWIFT

  # A minimal Xcode project generated locally on the new Mac.
  cat > "$PROJECT/project.pbxproj" <<PBX
// !\$*UTF8*\$!
{
	archiveVersion = 1;
	classes = {};
	objectVersion = 56;
	objects = {

/* Begin PBXBuildFile section */
		A00000000000000000000001 /* WeChatCloneProfileApp.swift in Sources */ = {isa = PBXBuildFile; fileRef = A00000000000000000000011 /* WeChatCloneProfileApp.swift */; };
		A00000000000000000000002 /* ContentView.swift in Sources */ = {isa = PBXBuildFile; fileRef = A00000000000000000000012 /* ContentView.swift */; };
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
		A00000000000000000000010 /* WeChatCloneProfile.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = WeChatCloneProfile.app; sourceTree = BUILT_PRODUCTS_DIR; };
		A00000000000000000000011 /* WeChatCloneProfileApp.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = WeChatCloneProfileApp.swift; sourceTree = "<group>"; };
		A00000000000000000000012 /* ContentView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ContentView.swift; sourceTree = "<group>"; };
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		A00000000000000000000020 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = ();
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		A00000000000000000000030 = {
			isa = PBXGroup;
			children = (
				A00000000000000000000031 /* WeChatCloneProfile */,
				A00000000000000000000032 /* Products */,
			);
			sourceTree = "<group>";
		};
		A00000000000000000000031 /* WeChatCloneProfile */ = {
			isa = PBXGroup;
			children = (
				A00000000000000000000011 /* WeChatCloneProfileApp.swift */,
				A00000000000000000000012 /* ContentView.swift */,
			);
			path = WeChatCloneProfile;
			sourceTree = "<group>";
		};
		A00000000000000000000032 /* Products */ = {
			isa = PBXGroup;
			children = (
				A00000000000000000000010 /* WeChatCloneProfile.app */,
			);
			name = Products;
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		A00000000000000000000040 /* WeChatCloneProfile */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = A00000000000000000000050;
			buildPhases = (
				A00000000000000000000021 /* Sources */,
				A00000000000000000000020 /* Frameworks */,
				A00000000000000000000022 /* Resources */,
			);
			buildRules = ();
			dependencies = ();
			name = WeChatCloneProfile;
			productName = WeChatCloneProfile;
			productReference = A00000000000000000000010;
			productType = "com.apple.product-type.application";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		A00000000000000000000060 /* Project object */ = {
			isa = PBXProject;
			attributes = {
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 2600;
				LastUpgradeCheck = 2600;
				TargetAttributes = {
					A00000000000000000000040 = { CreatedOnToolsVersion = 26.0; };
				};
			};
			buildConfigurationList = A00000000000000000000051;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (en, Base);
			mainGroup = A00000000000000000000030;
			productRefGroup = A00000000000000000000032;
			projectDirPath = "";
			projectRoot = "";
			targets = (A00000000000000000000040);
		};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		A00000000000000000000022 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = ();
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		A00000000000000000000021 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				A00000000000000000000001,
				A00000000000000000000002,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		A00000000000000000000070 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_STYLE = Automatic;
				DEVELOPMENT_TEAM = "${TEAM_ID}";
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_CFBundleDisplayName = WeChatCloneProfile;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"\$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				CURRENT_PROJECT_VERSION = 1;
				PRODUCT_BUNDLE_IDENTIFIER = "${BUNDLE_ID}";
				PRODUCT_NAME = "\$(TARGET_NAME)";
				SDKROOT = iphoneos;
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = 1;
			};
			name = Debug;
		};
		A00000000000000000000071 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_STYLE = Automatic;
				DEVELOPMENT_TEAM = "${TEAM_ID}";
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_CFBundleDisplayName = WeChatCloneProfile;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"\$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				CURRENT_PROJECT_VERSION = 1;
				PRODUCT_BUNDLE_IDENTIFIER = "${BUNDLE_ID}";
				PRODUCT_NAME = "\$(TARGET_NAME)";
				SDKROOT = iphoneos;
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = 1;
			};
			name = Release;
		};
		A00000000000000000000072 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				SDKROOT = iphoneos;
				SWIFT_VERSION = 5.0;
			};
			name = Debug;
		};
		A00000000000000000000073 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				SDKROOT = iphoneos;
				SWIFT_VERSION = 5.0;
			};
			name = Release;
		};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		A00000000000000000000050 = {
			isa = XCConfigurationList;
			buildConfigurations = (A00000000000000000000070, A00000000000000000000071);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		A00000000000000000000051 = {
			isa = XCConfigurationList;
			buildConfigurations = (A00000000000000000000072, A00000000000000000000073);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
/* End XCConfigurationList section */
	};
	rootObject = A00000000000000000000060;
}
PBX

  cat > "$PROJECT/xcshareddata/xcschemes/WeChatCloneProfile.xcscheme" <<'SCHEME'
<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.7">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries>
      <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
        <BuildableReference BuildableIdentifier="primary"
          BlueprintIdentifier="A00000000000000000000040"
          BuildableName="WeChatCloneProfile.app"
          BlueprintName="WeChatCloneProfile"
          ReferencedContainer="container:WeChatCloneProfile.xcodeproj"/>
      </BuildActionEntry>
    </BuildActionEntries>
  </BuildAction>
  <RunAction buildConfiguration="Debug"
    selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB"
    selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB"
    launchStyle="0" useCustomWorkingDirectory="NO"
    ignoresPersistentStateOnLaunch="NO"
    debugDocumentVersioning="YES"
    debugServiceExtension="internal"
    allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">
      <BuildableReference BuildableIdentifier="primary"
        BlueprintIdentifier="A00000000000000000000040"
        BuildableName="WeChatCloneProfile.app"
        BlueprintName="WeChatCloneProfile"
        ReferencedContainer="container:WeChatCloneProfile.xcodeproj"/>
    </BuildableProductRunnable>
  </RunAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES"/>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
SCHEME

  ok "Generated bootstrap Xcode project: $PROJECT"
}

ensure_bootstrap_project() {
  if [ ! -f "$PROJECT/project.pbxproj" ]; then
    note "No bootstrap project exists yet; generating it now..."
    create_bootstrap_project
  fi
}

project_team_id() {
  [ -f "$PROJECT/project.pbxproj" ] || return 0
  sed -nE 's/.*DEVELOPMENT_TEAM = "?([A-Z0-9]{10})"?;.*/\1/p' "$PROJECT/project.pbxproj" 2>/dev/null \
    | head -1 || true
}

team_id_from_profile() {
  local profile="$1"
  [ -f "$profile" ] || return 1

  local decoded app_id team_id expiration now
  decoded="$(mktemp "${TMPDIR:-/tmp}/wechat2-profile.XXXXXX.plist")"
  if ! security cms -D -i "$profile" > "$decoded" 2>/dev/null; then
    rm -f "$decoded"
    return 1
  fi

  app_id="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$decoded" 2>/dev/null || true)"
  team_id="$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "$decoded" 2>/dev/null || true)"

  if [ -z "$team_id" ] || [ -z "$app_id" ]; then
    rm -f "$decoded"
    return 1
  fi

  case "$app_id" in
    *."$BUNDLE_ID") ;;
    *)
      rm -f "$decoded"
      return 1
      ;;
  esac

  expiration="$(python3 - "$decoded" <<'PY'
import plistlib, sys
from datetime import timezone
with open(sys.argv[1], "rb") as f:
    p = plistlib.load(f)
dt = p.get("ExpirationDate")
if dt is None:
    print(0)
else:
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    print(int(dt.timestamp()))
PY
)"
  now="$(date +%s)"
  rm -f "$decoded"

  [ "${expiration:-0}" -gt "$now" ] || return 1
  printf '%s\n' "$team_id"
}

matching_profile_team_id() {
  local p team

  # Strongest signal after the user successfully runs the bootstrap app in Xcode.
  while IFS= read -r p; do
    team="$(team_id_from_profile "$p" 2>/dev/null || true)"
    if [ -n "$team" ]; then
      printf '%s\n' "$team"
      return 0
    fi
  done < <(
    find "$HOME/Library/Developer/Xcode/DerivedData" \
         "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" \
         "$HOME/Library/MobileDevice/Provisioning Profiles" \
         -type f \( -name 'embedded.mobileprovision' -o -name '*.mobileprovision' \) \
         -print 2>/dev/null
  )

  return 1
}

certificate_team_id() {
  security find-identity -v -p codesigning 2>/dev/null \
    | grep '"Apple Development:' \
    | head -1 \
    | sed -nE 's/.*\(([A-Z0-9]{10})\)".*/\1/p' || true
}

discover_team_id() {
  DISCOVERED_TEAM="${TEAM_ID:-}"
  TEAM_SOURCE=""

  if [ -n "$DISCOVERED_TEAM" ]; then
    TEAM_SOURCE="config"
  fi

  # A live, unexpired provisioning profile for this exact bundle ID is the
  # strongest automatic signal after the bootstrap test app has run successfully.
  if [ -z "$DISCOVERED_TEAM" ]; then
    DISCOVERED_TEAM="$(matching_profile_team_id 2>/dev/null || true)"
    [ -n "$DISCOVERED_TEAM" ] && TEAM_SOURCE="matching-profile"
  fi

  if [ -z "$DISCOVERED_TEAM" ]; then
    DISCOVERED_TEAM="$(project_team_id)"
    [ -n "$DISCOVERED_TEAM" ] && TEAM_SOURCE="project"
  fi

  # Certificate-only detection is last because Keychain may contain migrated or stale identities.
  if [ -z "$DISCOVERED_TEAM" ]; then
    DISCOVERED_TEAM="$(certificate_team_id)"
    [ -n "$DISCOVERED_TEAM" ] && TEAM_SOURCE="certificate"
  fi

  if [ -n "$DISCOVERED_TEAM" ]; then
    ok "Development Team: $DISCOVERED_TEAM (source: $TEAM_SOURCE)"
    return 0
  fi

  return 1
}

write_team_into_project() {
  local tid="$1"
  python3 - "$PROJECT/project.pbxproj" "$tid" <<'PY'
import sys, re
from pathlib import Path
p = Path(sys.argv[1])
team = sys.argv[2]
s = p.read_text()
s = re.sub(r'DEVELOPMENT_TEAM = "[^"]*";', f'DEVELOPMENT_TEAM = "{team}";', s)
s = re.sub(r'DEVELOPMENT_TEAM = [A-Z0-9]*;', f'DEVELOPMENT_TEAM = "{team}";', s)
p.write_text(s)
PY
}

list_physical_iphones() {
  xcrun xctrace list devices 2>/dev/null \
    | grep -E 'iPhone.*\([[:alnum:]-]{20,}\)$' \
    | grep -v Simulator || true
}

pick_device() {
  if [ -n "${WECHAT2_DEVICE_ID:-}" ]; then
    DEVICE_LINE="$(list_physical_iphones | grep -F "(${WECHAT2_DEVICE_ID})" | head -1 || true)"
    [ -n "$DEVICE_LINE" ] || die "Configured iPhone ${WECHAT2_DEVICE_ID} is not currently online/visible to Xcode tools."
    DEVICE_ID="$WECHAT2_DEVICE_ID"
    ok "Using configured device: $DEVICE_LINE"
    return 0
  fi

  DEVICE_TMP="$WORK_DIR/devices.txt"
  mkdir -p "$WORK_DIR"
  list_physical_iphones > "$DEVICE_TMP"

  COUNT="$(grep -c . "$DEVICE_TMP" 2>/dev/null || true)"
  [ "$COUNT" -gt 0 ] || die "No physical iPhone detected. Connect by USB, unlock it, and tap Trust."

  if [ "$COUNT" -eq 1 ]; then
    DEVICE_LINE="$(head -1 "$DEVICE_TMP")"
  else
    echo
    echo "Connected iPhones:"
    nl -w2 -s') ' "$DEVICE_TMP"
    echo
    read -r -p "Choose device [1-$COUNT]: " choice
    case "$choice" in
      ''|*[!0-9]*) die "Invalid device selection." ;;
    esac
    [ "$choice" -ge 1 ] && [ "$choice" -le "$COUNT" ] || die "Invalid device selection."
    DEVICE_LINE="$(sed -n "${choice}p" "$DEVICE_TMP")"
  fi

  DEVICE_ID="$(printf '%s\n' "$DEVICE_LINE" | sed -E 's/.*\(([[:alnum:]-]{20,})\)$/\1/')"
  [ -n "$DEVICE_ID" ] || die "Could not parse the iPhone UDID."
  ok "Using device: $DEVICE_LINE"
}

show_destinations() {
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -showdestinations 2>&1 || true
}

is_xcode_destination_ready() {
  show_destinations | grep -Eq "id:[[:space:]]*$DEVICE_ID([,}[:space:]]|$)"
}

ensure_xcode_destination_ready() {
  if is_xcode_destination_ready; then
    ok "iPhone is available as an Xcode run destination."
    return 0
  fi

  if [ "${WECHAT2_NONINTERACTIVE:-0}" = "1" ]; then
    die "iPhone $DEVICE_ID is visible to xctrace but is not currently a usable Xcode destination. The scheduled job will retry later."
  fi

  echo
  warn "The iPhone is visible to xctrace, but Xcode does not yet list it as a usable iOS destination."
  echo
  echo "This normally means the new Mac/iPhone development pairing is not finished."
  echo "The generated provisioning project will be opened in Xcode now:"
  echo "  $PROJECT"
  echo
  echo "In Xcode:"
  echo "  1) Make sure the iPhone stays connected by USB and unlocked."
  echo "  2) Accept Trust prompts on both Mac/iPhone if shown."
  echo "  3) Make sure Developer Mode is enabled on the iPhone."
  echo "  4) Open Xcode's device-management UI (Device Hub / Devices and Simulators)."
  echo "  5) Wait until the iPhone reports Ready/Connected and appears as a run destination."
  echo

  open "$PROJECT" >/dev/null 2>&1 || open -a Xcode >/dev/null 2>&1 || true

  attempt=1
  while [ "$attempt" -le 3 ]; do
    read -r -p "When the iPhone is Ready in Xcode, press Enter to retry [$attempt/3]..." _
    if is_xcode_destination_ready; then
      ok "iPhone is now available as an Xcode run destination."
      return 0
    fi
    warn "Xcode still does not list device $DEVICE_ID as a usable destination."
    attempt=$((attempt + 1))
  done

  echo
  echo "Current Xcode destinations:"
  show_destinations
  die "iPhone development pairing is still incomplete. Finish pairing in Xcode, then rerun the installer."
}

prepare_team_interactively_if_needed() {
  if discover_team_id; then
    write_team_into_project "$DISCOVERED_TEAM"
    return 0
  fi

  if [ "${WECHAT2_NONINTERACTIVE:-0}" = "1" ]; then
    die "No Apple Development Team is available for unattended refresh. Open Xcode and complete the one-time signing setup."
  fi

  echo
  echo "===================================================="
  echo "One-time Apple signing setup is required"
  echo "===================================================="
  echo
  echo "This is a brand-new Mac, so no Apple Development Team/certificate"
  echo "has been created yet. The bootstrap project has already been"
  echo "generated for you:"
  echo
  echo "  $PROJECT"
  echo
  echo "The remaining Apple step cannot be completed without your"
  echo "interactive account authorization."
  echo
  echo "Xcode will open now. Do this once:"
  echo "  1) Xcode > Settings > Accounts: sign in."
  echo "  2) In the project, select TARGETS > WeChatCloneProfile."
  echo "  3) Signing & Capabilities > Team: choose your Personal Team."
  echo "  4) Keep Automatically manage signing enabled."
  echo "  5) Select the connected iPhone and press Run once."
  echo
  echo "After the test app opens on the iPhone, quit Xcode and run"
  echo "WeChat2_Manager.command again. From then on the scripts can"
  echo "discover and reuse the Team automatically."
  echo

  open "$PROJECT"
  exit 3
}

build_bootstrap_profile() {
  mkdir -p "$WORK_DIR"
  rm -rf "$BUILD_DIR"

  ensure_xcode_destination_ready

  note "Using Xcode to register/provision this iPhone..."

  mkdir -p "$STATE_DIR"
  XCODE_LOG="$STATE_DIR/last_xcodebuild.log"

  set +e
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "id=$DEVICE_ID" \
    -derivedDataPath "$BUILD_DIR" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$DISCOVERED_TEAM" \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
    CODE_SIGN_STYLE=Automatic \
    build 2>&1 | tee "$XCODE_LOG"
  rc=${PIPESTATUS[0]}
  set -e

  if [ "$rc" -ne 0 ]; then
    if grep -q 'No Account for Team' "$XCODE_LOG"; then
      echo
      warn "Xcode does not have an authenticated account for Team $DISCOVERED_TEAM."
      if [ "${TEAM_SOURCE:-}" = "certificate" ]; then
        echo "That Team ID was inferred only from an Apple Development certificate in Keychain."
        echo "A migrated/stale certificate does not prove the matching Apple Account is signed into Xcode."
      fi
      echo
      echo "One-time fix:"
      echo "  1) Open Xcode > Settings > Accounts and sign into the Apple Account you want to use."
      echo "  2) In the generated project:"
      echo "       TARGETS > WeChatCloneProfile > Signing & Capabilities"
      echo "  3) Choose the Personal Team shown by that signed-in account."
      echo "  4) Keep Automatically manage signing enabled."
      echo "  5) Run the small test app once on the connected iPhone."
      echo
      echo "The project will be opened now:"
      echo "  $PROJECT"
      echo
      open "$PROJECT" >/dev/null 2>&1 || open -a Xcode >/dev/null 2>&1 || true
      exit 3
    fi

    echo
    echo "Xcode provisioning failed."
    echo "Open the generated project:"
    echo "  $PROJECT"
    echo
    echo "Verify Xcode > Settings > Accounts is signed in and"
    echo "Signing & Capabilities uses your Personal Team."
    echo
    echo "Full build log:"
    echo "  $XCODE_LOG"
    exit "$rc"
  fi

  BOOTSTRAP_APP="$(find "$BUILD_DIR/Build/Products" -type d -name 'WeChatCloneProfile.app' | head -1)"
  [ -n "$BOOTSTRAP_APP" ] || die "Could not locate the built bootstrap app."

  PROFILE="$BOOTSTRAP_APP/embedded.mobileprovision"
  [ -f "$PROFILE" ] || die "No embedded provisioning profile found in bootstrap app."

  PROFILE_PLIST="$WORK_DIR/profile.plist"
  ENTITLEMENTS="$WORK_DIR/profile-entitlements.plist"

  security cms -D -i "$PROFILE" > "$PROFILE_PLIST"
  plutil -extract Entitlements xml1 -o "$ENTITLEMENTS" "$PROFILE_PLIST"

  ok "Provisioning profile created by Xcode."
}

find_signing_identity() {
  IDENTITY_HASH=""
  IDENTITY_DESC=""

  # Xcode has just successfully built and signed BOOTSTRAP_APP. Use the exact
  # signing authority from that app instead of assuming the certificate CN's
  # parenthesized identifier is the Team ID. On Personal Teams those values can
  # differ even though TeamIdentifier/application-identifier are correct.
  if [ -n "${BOOTSTRAP_APP:-}" ] && [ -d "$BOOTSTRAP_APP" ]; then
    BOOTSTRAP_TEAM="$(
      /usr/bin/codesign -dv --verbose=4 "$BOOTSTRAP_APP" 2>&1 \
        | sed -n 's/^TeamIdentifier=//p' \
        | head -1
    )"
    BOOTSTRAP_AUTHORITY="$(
      /usr/bin/codesign -dv --verbose=4 "$BOOTSTRAP_APP" 2>&1 \
        | sed -n 's/^Authority=//p' \
        | head -1
    )"

    if [ -n "${DISCOVERED_TEAM:-}" ] && [ -n "$BOOTSTRAP_TEAM" ] && [ "$BOOTSTRAP_TEAM" != "$DISCOVERED_TEAM" ]; then
      die "Xcode signed the bootstrap app with Team $BOOTSTRAP_TEAM, but the selected provisioning profile reports Team $DISCOVERED_TEAM. Re-run setup and use one consistent Personal Team."
    fi

    if [ -n "$BOOTSTRAP_AUTHORITY" ]; then
      IDENTITY_HASH="$(
        security find-identity -v -p codesigning 2>/dev/null \
          | awk -v auth="$BOOTSTRAP_AUTHORITY" 'index($0, "\"" auth "\"") {print $2; exit}'
      )"
      if [ -n "$IDENTITY_HASH" ]; then
        IDENTITY_DESC="$BOOTSTRAP_AUTHORITY"
      fi
    fi
  fi

  # Fallback: if the exact Xcode authority could not be mapped, choose an Apple
  # Development identity and later rely on the embedded profile/codesign checks.
  # Do not match the certificate CN's parenthesized value to TeamIdentifier.
  if [ -z "$IDENTITY_HASH" ]; then
    IDENTITY_HASH="$(
      security find-identity -v -p codesigning 2>/dev/null \
        | awk '/"Apple Development:/{print $2; exit}'
    )"
    if [ -n "$IDENTITY_HASH" ]; then
      IDENTITY_DESC="$(
        security find-identity -v -p codesigning 2>/dev/null \
          | awk -v h="$IDENTITY_HASH" '$2==h {$1="";$2=""; sub(/^ +/,""); print; exit}'
      )"
    fi
  fi

  [ -n "$IDENTITY_HASH" ] || die "No usable Apple Development signing identity was found after Xcode successfully provisioned the bootstrap app."

  ok "Signing identity: ${IDENTITY_DESC:-$IDENTITY_HASH}"
  if [ -n "${BOOTSTRAP_TEAM:-}" ]; then
    ok "Signing TeamIdentifier: $BOOTSTRAP_TEAM"
  fi
}

check_ipa_cryptid() {
  [ -f "$IPA" ] || die "Missing IPA: $IPA"

  rm -rf "$WORK_DIR/check"
  mkdir -p "$WORK_DIR/check"
  unzip -q "$IPA" -d "$WORK_DIR/check"

  CHECK_APP="$(find "$WORK_DIR/check/Payload" -maxdepth 1 -type d -name '*.app' | head -1)"
  [ -n "$CHECK_APP" ] || die "IPA does not contain Payload/*.app"

  CHECK_PLIST="$CHECK_APP/Info.plist"
  CHECK_EXE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$CHECK_PLIST")"
  [ -f "$CHECK_APP/$CHECK_EXE" ] || die "Main executable is missing."

  CRYPTID="$(
    xcrun otool -l "$CHECK_APP/$CHECK_EXE" \
      | awk '
          /LC_ENCRYPTION_INFO/ {inside=1}
          /LC_ENCRYPTION_INFO_64/ {inside=1}
          inside && /cryptid/ {print $2; exit}
        '
  )"

  [ "${CRYPTID:-unknown}" = "0" ] || die "IPA main executable reports cryptid=${CRYPTID:-unknown}; this workflow requires an authorized re-signable IPA with cryptid 0."
  ok "IPA cryptid check passed (cryptid 0)."
}

rewrite_plist_string_refs() {
  local app="$1"
  local old_id="$2"
  local new_id="$3"

  while IFS= read -r plist; do
    plutil -convert xml1 "$plist" >/dev/null 2>&1 || continue
    if grep -qF "$old_id" "$plist" 2>/dev/null; then
      python3 - "$plist" "$old_id" "$new_id" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
old, new = sys.argv[2], sys.argv[3]
s = p.read_text(errors="ignore")
p.write_text(s.replace(old, new))
PY
    fi
  done < <(find "$app" -type f -name '*.plist')
}

sign_nested_code() {
  local app="$1"

  note "Signing nested frameworks and dylibs..."

  while IFS= read -r item; do
    [ -e "$item" ] || continue
    codesign --force --sign "$IDENTITY_HASH" --timestamp=none "$item"
  done < <(
    find "$app" -depth \
      \( -type d -name '*.framework' -o -type f -name '*.dylib' \)
  )
}

verify_signed_app() {
  local app="$1"
  codesign --verify --deep --strict --verbose=2 "$app"
  ok "Code signature verification passed."
}


ensure_state_dir() {
  mkdir -p "$STATE_DIR"
}

save_last_device_id() {
  local device_id="$1"
  ensure_state_dir
  printf '%s\n' "$device_id" > "$LAST_DEVICE_FILE"
}

read_last_device_id() {
  [ -f "$LAST_DEVICE_FILE" ] || return 1
  head -1 "$LAST_DEVICE_FILE"
}

save_autorefresh_device_id() {
  local device_id="$1"
  ensure_state_dir
  printf '%s\n' "$device_id" > "$AUTO_REFRESH_DEVICE_FILE"
}

read_autorefresh_device_id() {
  [ -f "$AUTO_REFRESH_DEVICE_FILE" ] || return 1
  head -1 "$AUTO_REFRESH_DEVICE_FILE"
}

record_profile_expiration_state() {
  local profile_plist="$1"
  [ -f "$profile_plist" ] || return 1
  ensure_state_dir

  python3 - "$profile_plist" "$PROFILE_EXPIRY_FILE" "$PROFILE_EXPIRY_ISO_FILE" <<'PY'
import plistlib
import sys
from datetime import timezone

profile_path, epoch_path, iso_path = sys.argv[1:4]
with open(profile_path, "rb") as f:
    data = plistlib.load(f)

dt = data.get("ExpirationDate")
if dt is None:
    raise SystemExit("Provisioning profile has no ExpirationDate")
if dt.tzinfo is None:
    dt = dt.replace(tzinfo=timezone.utc)

epoch = int(dt.timestamp())
with open(epoch_path, "w") as f:
    f.write(str(epoch) + "\n")
with open(iso_path, "w") as f:
    f.write(dt.astimezone(timezone.utc).isoformat() + "\n")
PY

  ok "Recorded provisioning expiration: $(profile_expiration_human 2>/dev/null || cat "$PROFILE_EXPIRY_ISO_FILE")"
}

read_profile_expiration_epoch() {
  [ -f "$PROFILE_EXPIRY_FILE" ] || return 1
  local value
  value="$(head -1 "$PROFILE_EXPIRY_FILE" 2>/dev/null || true)"
  case "$value" in
    ''|*[!0-9]*) return 1 ;;
    *) printf '%s\n' "$value" ;;
  esac
}

profile_expiration_human() {
  local epoch
  epoch="$(read_profile_expiration_epoch)" || return 1
  date -r "$epoch" '+%Y-%m-%d %H:%M:%S %Z'
}

profile_seconds_remaining() {
  local epoch now
  epoch="$(read_profile_expiration_epoch)" || return 1
  now="$(date +%s)"
  echo $((epoch - now))
}


record_embedded_profile_expiration() {
  local embedded_profile="$1"
  [ -f "$embedded_profile" ] || return 1
  ensure_state_dir
  local decoded="$STATE_DIR/recovered-profile.plist"
  if security cms -D -i "$embedded_profile" > "$decoded" 2>/dev/null; then
    record_profile_expiration_state "$decoded"
    rm -f "$decoded"
    return 0
  fi
  rm -f "$decoded"
  return 1
}

recover_profile_expiration_state() {
  if read_profile_expiration_epoch >/dev/null 2>&1; then
    return 0
  fi

  ensure_state_dir

  # 1) A decoded provisioning profile from a previous install/refresh.
  if [ -f "$WORK_DIR/profile.plist" ]; then
    if record_profile_expiration_state "$WORK_DIR/profile.plist" >/dev/null 2>&1; then
      return 0
    fi
  fi

  # 2) The last extracted/signed app still in .work.
  local embedded
  embedded="$(find "$WORK_DIR/sign/Payload" -maxdepth 3 -type f -name embedded.mobileprovision 2>/dev/null | head -1 || true)"
  if [ -n "$embedded" ] && record_embedded_profile_expiration "$embedded" >/dev/null 2>&1; then
    return 0
  fi

  # 3) The last bootstrap app built by Xcode.
  embedded="$(find "$BUILD_DIR/Build/Products" -maxdepth 5 -type f -name embedded.mobileprovision 2>/dev/null | head -1 || true)"
  if [ -n "$embedded" ] && record_embedded_profile_expiration "$embedded" >/dev/null 2>&1; then
    return 0
  fi

  # 4) A previously exported signed IPA.
  local signed_ipa="$OUTPUT_DIR/WeChat2-signed.ipa"
  if [ -f "$signed_ipa" ]; then
    local member tmp_profile
    member="$(unzip -Z1 "$signed_ipa" 2>/dev/null | grep -E '^Payload/[^/]+\.app/embedded\.mobileprovision$' | head -1 || true)"
    if [ -n "$member" ]; then
      tmp_profile="$STATE_DIR/recovered-embedded.mobileprovision"
      if unzip -p "$signed_ipa" "$member" > "$tmp_profile" 2>/dev/null; then
        if record_embedded_profile_expiration "$tmp_profile" >/dev/null 2>&1; then
          rm -f "$tmp_profile"
          return 0
        fi
      fi
      rm -f "$tmp_profile"
    fi
  fi

  return 1
}

install_app_with_retry() {
  local device_id="$1"
  local app_path="$2"
  local install_log="$STATE_DIR/last_devicectl_install.log"
  local attempt=1
  local max_attempts=5
  local delay=0
  local rc

  ensure_state_dir

  while [ "$attempt" -le "$max_attempts" ]; do
    if [ "$attempt" -gt 1 ]; then
      case "$attempt" in
        2) delay=5 ;;
        3) delay=10 ;;
        4) delay=20 ;;
        *) delay=30 ;;
      esac
      note "Retrying iPhone install in ${delay}s (attempt $attempt/$max_attempts)..."
      sleep "$delay"
    fi

    : > "$install_log"
    set +e
    xcrun devicectl device install app --device "$device_id" "$app_path" 2>&1 | tee "$install_log"
    rc=${PIPESTATUS[0]}
    set -e

    if [ "$rc" -eq 0 ] && ! grep -Eq 'ERROR:|Failed to allocate RSD device|0xE8000003' "$install_log"; then
      ok "App install completed."
      return 0
    fi

    if grep -Eq 'Failed to allocate RSD device|0xE8000003|-402653181|CoreDeviceError error -1' "$install_log"; then
      warn "CoreDevice/RSD transport is temporarily unavailable (0xE8000003)."

      if [ "${WECHAT2_NONINTERACTIVE:-0}" != "1" ] && [ "$attempt" -eq 1 ]; then
        echo "Keep the iPhone unlocked and connected. If USB is available, unplug/replug"
        echo "the cable once before the next retry. No re-signing is needed."
      fi

      attempt=$((attempt + 1))
      continue
    fi

    echo
    echo "devicectl install failed with a non-retryable error."
    echo "Full install log:"
    echo "  $install_log"
    return "${rc:-1}"
  done

  echo
  echo "iPhone install still failed after $max_attempts attempts because CoreDevice/RSD"
  echo "could not allocate a device session (0xE8000003)."
  echo "The signed app is still valid and does not need to be re-signed."
  echo "Try keeping the iPhone unlocked and reconnecting USB, then rerun the install."
  echo "Full install log:"
  echo "  $install_log"
  return 75
}
