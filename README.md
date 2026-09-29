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


## Smart auto-refresh schedule

Manager options:

```text
5) Install smart auto-refresh schedule
6) Uninstall smart auto-refresh schedule
7) Smart auto-refresh status
```

You can also run:

```bash
bash setup_wechat2_smart_autorefresh.sh install
bash setup_wechat2_smart_autorefresh.sh uninstall
bash setup_wechat2_smart_autorefresh.sh status
```

The schedule uses a per-user LaunchAgent:

```text
com.ilovefood2.wechat2.smart-autorefresh
```

Behavior:

- The actual provisioning expiration time is recorded after every successful install/refresh.
- The LaunchAgent wakes once per hour, but before the final 24 hours it only reads the local expiry timestamp and exits immediately.
- During roughly the first six days of a seven-day Personal Team signature, it does **not** start Xcode, check the iPhone, re-sign, or reinstall.
- Once the signature enters its final 24 hours, it attempts a refresh once per hour.
- If the target iPhone is offline/not visible, the attempt is skipped and the next hourly run retries.
- If the Mac is asleep/offline, launchd resumes the schedule when the Mac is running again; `RunAtLoad` also performs a check when the agent is loaded after login.
- If Apple/Xcode/network provisioning fails, the schedule remains installed and retries the next hour.
- After a successful refresh, the new expiry is recorded. Subsequent hourly launches go back to the lightweight idle check until the next final-24-hour window.

The scheduled refresh is intentionally non-interactive. If Xcode pairing, Developer Mode, the Apple Account, or the Development Team requires user attention, the background attempt fails safely and retries later rather than opening prompts.

The target iPhone is saved when you install the schedule. Re-run **Install smart auto-refresh schedule** if you want to change the target phone.

Log:

```text
~/Library/Logs/WeChat2SmartAutoRefresh.log
```

The LaunchAgent stores the absolute path to this checkout. Do not move or delete the repository folder while the schedule is installed; uninstall/reinstall the schedule after moving it.
