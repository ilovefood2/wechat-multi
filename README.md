# WeChat Multi — macOS branch

Creates a second macOS WeChat application at `/Applications/WeChat2.app` while leaving the official `/Applications/WeChat.app` untouched.

## Usage

1. Install official WeChat in `/Applications/WeChat.app`.
2. Double-click `Install-WeChat2.command`, or run:

```bash
chmod +x Install-WeChat2.command
./Install-WeChat2.command
```

The script:

- clones WeChat with `ditto`
- prevents the invalid `WeChat2.app/WeChat.app` nested layout
- changes the clone Bundle ID to `com.kj.wechat2`
- changes the display name to `WeChat 2`
- updates plist string references to the original Bundle ID
- removes extended attributes / old signatures
- applies an ad-hoc signature
- verifies the resulting bundle
- launches the second copy

If `WeChat2.app` already exists, it is backed up with a timestamp before rebuilding.

## Updating

After the official WeChat app updates, run the installer again to rebuild the clone from the current official version.
