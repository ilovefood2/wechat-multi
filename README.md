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

Option 3 is treated as a **validated renewal** when a successful-install receipt
already exists for the selected iPhone: Xcode must provide a profile whose
`ExpirationDate` genuinely advances beyond the installed receipt. Re-signing
with the same cached expiry is not reported as a successful refresh.

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

### Two-stage scheduling

The current scheduler uses two per-user LaunchAgents:

```text
com.ilovefood2.wechat2.autorefresh.wakeup
com.ilovefood2.wechat2.autorefresh.retry
```

The wake agent is scheduled for the verified installed profile expiry minus the
renewal window (24 hours by default). During the quiet phase, the hourly retry
agent is **not loaded at all**. The wake agent may perform a lightweight
catch-up check when it is loaded after login, but there is no hourly polling,
Xcode build, iPhone check, signing, or reinstall during the quiet phase.

When the renewal window opens, the retry agent is loaded and runs once per
hour until renewal succeeds. If the Mac/iPhone/network is unavailable, it keeps
retrying. After success, the retry agent is unloaded and the next wake-up is
programmed from the newly verified expiry.

The renewal window is configurable in `config.env`:

```bash
AUTO_REFRESH_WINDOW_SECONDS="86400"
```

### Renewal correctness checks

Automatic renewal is deliberately stricter than a normal manual install:

- The previous **successful-install receipt** is the source of truth for expiry.
  A cached Xcode profile by itself is not treated as proof of what is installed.
- When renewal is due, matching local provisioning-profile cache entries for the
  exact Bundle ID / Team / iPhone are backed up transactionally before asking
  Xcode for a replacement.
- The replacement profile must have a genuinely later `ExpirationDate` than
  the previously installed profile and must extend beyond the renewal window.
  A different profile UUID alone is not accepted as renewal.
- Interrupted/failed renewal can restore missing old cache entries from
  `.state/profile-backups/`.
- Before installation, the signed app validates the top-level app and every
  embedded `.app` / `.appex` that remains: Bundle ID, Team, target-device
  authorization, expiration, development entitlement, and an allowed
  Apple Development certificate/private key.
- With the default `REMOVE_EXTENSIONS="1"`, those embedded extensions are
  removed, so the validated manifest normally contains only the main app.
  If extensions are kept, each one must have its own valid development profile.
- Expiry state is committed **only after** `devicectl` reports a successful
  installation. A successful signature/export followed by a failed iPhone
  install does not advance the scheduler state.

The successful-install receipt is stored at:

```text
.state/install_receipt.json
```

The effective expiry is the earliest expiry among all validated embedded app
profiles in that receipt.

Logs:

```text
~/Library/Logs/WeChat2SmartAutoRefresh.log
```

Uninstalling the smart schedule removes its LaunchAgents and schedule metadata,
but leaves WeChat 2, the install receipt/history, and provisioning-profile backup
history untouched.

The LaunchAgent stores the absolute path to this checkout. Do not move or delete
the repository folder while the schedule is installed; uninstall/reinstall the
schedule after moving it.


## Paired-device diagnostics

Manager option:

```text
9) Show paired devices / device info
```

or run:

```bash
bash show_paired_devices.command
```

This is read-only. It shows:

- CoreDevice's paired/known device list;
- physical iPhones currently visible to Xcode tools;
- device identifier and selected CoreDevice connection/device details;
- whether each visible iPhone is currently a usable Xcode run destination;
- WeChat developer installs returned by CoreDevice, including Bundle ID/version rows;
- which device is the last successful install target and which is the smart auto-refresh target;
- the verified provisioning expiry from this checkout's successful-install receipt, when it belongs to that iPhone;
- Apple Development signing identities available on the current Mac.

A device can remain in the paired/known list while being offline, locked, disconnected,
or otherwise unavailable as an Xcode run destination.

## Refreshing from a different Mac

The Apple development signing setup is **per Mac**.

If you clone/copy this repository to another Mac and choose option 3 immediately, that Mac may have unrelated or migrated Apple Development certificates in Keychain. The scripts deliberately do **not** trust those certificates as proof of an authenticated Xcode Team.

On each new Mac, do the one-time setup first:

```text
1) New Mac / new iPhone setup
```

Select the Personal Team in Xcode and run the small bootstrap test app once on that Mac. Xcode will create a live provisioning profile for this Bundle ID. After that, options 2/3 and smart auto-refresh can safely discover and reuse the verified Team on that Mac.

A certificate-only Team ID is treated as a hint and will not be selected automatically.
