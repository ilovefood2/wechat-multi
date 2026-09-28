# WeChat 2 iPhone Deployment Kit — New Mac Edition

This version is designed for a **brand-new Mac**. It does **not** require a pre-existing Xcode project.

The first setup script generates its own minimal provisioning project under:

`.generated/WeChatCloneProfile/WeChatCloneProfile.xcodeproj`

## Before the first run

Apple requires some interactive authorization on a new Mac:

1. Install the full Xcode app in `/Applications/Xcode.app`.
2. Open Xcode once and complete first-run setup.
3. Xcode > Settings > Accounts: sign into your Apple Account.
4. Connect the new iPhone by USB, unlock it, and tap **Trust**.
5. Enable **Developer Mode** on the iPhone if requested.

## First run

Double-click:

`WeChat2_Manager.command`

Choose:

`1) New Mac / new iPhone setup`

The script automatically creates the Xcode bootstrap project.

### If the Mac has never created an Apple Development certificate/team before

The script will automatically open the generated project.

Do this one time in Xcode:

1. Select `WeChatCloneProfile` under TARGETS.
2. Open **Signing & Capabilities**.
3. Keep **Automatically manage signing** checked.
4. Choose your **Personal Team**.
5. Select the connected iPhone and press **Run** once.

When the small test app opens on the iPhone, quit Xcode and run the Manager again.

After this, the scripts can discover your Team ID and Apple Development certificate automatically.

## IPA

Put an IPA you are authorized to use at:

`IPA/WeChat.ipa`

The installer checks the main executable and requires `cryptid 0`.

This kit does not download, decrypt, or include WeChat.

## Install

Manager option:

`2) Sign + install WeChat 2`

The script will:

- detect the connected iPhone
- obtain a fresh Xcode provisioning profile
- verify the source IPA is cryptid 0
- change the main Bundle ID
- optionally remove embedded extensions
- sign nested frameworks/dylibs
- sign the main app with your Apple Development identity/profile
- verify the signature
- install with Xcode's `devicectl`
- optionally export `Output/WeChat2-signed.ipa`

## Refresh

Run Manager option 3 before development provisioning expires.

## Notes

`REMOVE_EXTENSIONS="1"` is the default. This removes PlugIns, Watch components,
AppClips and similar embedded extensions because those can require separate App IDs,
profiles and entitlement sets.

A separately signed clone with a different Bundle ID does not automatically inherit
the official app's push-notification configuration, so background notifications may
not behave like the App Store installation.

## New Mac device pairing check

The installer now verifies the selected iPhone appears in `xcodebuild -showdestinations`, not just `xctrace list devices`.
If the phone is visible to macOS but not yet usable by Xcode, the script opens the generated project and waits for you to finish Trust / Developer Mode / Device Hub pairing before retrying.
