# Installing on macOS

Version 2.1.0 supports macOS 14 Sonoma or later. Liquid Glass requires macOS 26.
Choose arm64 for Apple Silicon (M-series) or x86_64 for Intel (Apple menu →
About This Mac). Download the matching DMG and SHA-256 file from the package
workflow artifacts or a release, when available.

## Verify and install

In the directory containing both downloaded files:

```sh
shasum -a 256 -c Keepy_2.1.0_arm64.dmg.sha256
```

Substitute x86_64 for an Intel download. The checksum detects download errors;
it is only as trustworthy as the source from which you obtained it.
Open the DMG and drag Keepy.app into Applications.

Current locally built packages are ad-hoc signed and are not notarized.
If Gatekeeper blocks the app, use System Settings → Privacy & Security →
Open Anyway after attempting to open it. Only do this for a build you trust.
Do not disable Gatekeeper system-wide.

## Upgrade from bunch-of-keys

Quit the old application before replacing it. Install Keepy.app and remove
the old bunch-of-keys.app bundle from Applications. Back up
`~/Library/Application Support/bunch-of-keys/` first. Keepy discovers the
existing registry and vaults in the same locations and preserves their encrypted
format. Choose the existing vault and unlock with the same master password.
The app UI is native; window size and old webview appearance preferences are
replaced with native Settings. The 2.x app requires a newer macOS version.

If launch at login was enabled in 1.x, disable it in the old app before replacing
it, then enable Launch at login in 2.x Settings. This moves startup registration
from the legacy LaunchAgent to the macOS ServiceManagement Login Item.

## Remove

Disable Launch at login in Settings, quit, then remove the app from Applications.
Your encrypted data stays in Application Support. Remove that directory only if
you deliberately want to erase your vaults and have made any necessary backups.
