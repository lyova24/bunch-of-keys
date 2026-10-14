# Installing on macOS

Version 2.1.2 supports macOS 14 Sonoma or later. Liquid Glass requires macOS 26.
Choose arm64 for Apple Silicon (M-series) or x86_64 for Intel (Apple menu →
About This Mac). Download the matching DMG and SHA-256 file from the package
workflow artifacts or a release, when available.

## Verify and install

In the directory containing both downloaded files:

```sh
shasum -a 256 -c Keepy_2.1.2_arm64.dmg.sha256
```

Substitute x86_64 for an Intel download. The checksum detects download errors;
it is only as trustworthy as the source from which you obtained it.
Open the DMG and drag Keepy.app into Applications.

Current locally built packages are ad-hoc signed and are not notarized.
If Gatekeeper blocks the app, use System Settings → Privacy & Security →
Open Anyway after attempting to open it. Only do this for a build you trust.
Do not disable Gatekeeper system-wide.

## Upgrade

Quit the previous application and back up your data before replacing the app.
Install Keepy.app into Applications. On first launch, earlier data and backup
folders are moved automatically into `~/Library/Application Support/Keepy/`
and `Keepy-backups/`, preserving file contents and permissions. Select your
existing vault and unlock it with the same master password.

If the previous service is still running or both data locations contain files,
the migration stops without overwriting either copy. Quit the previous service
or resolve the duplicate data folders before retrying.

When upgrading from an older bundle identity, disable Launch at login in the
previous app first, then enable it again in Keepy Settings after installation.
The native 2.x app requires macOS 14 or later.

## Remove

Disable Launch at login in Settings, quit, then remove the app from Applications.
Your encrypted data stays in Application Support. Remove that directory only if
you deliberately want to erase your vaults and have made any necessary backups.
