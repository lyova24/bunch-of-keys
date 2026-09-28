# Installing on macOS

`bunch-of-keys` 1.7.0 is distributed as separate unsigned DMG images for
Apple Silicon and Intel Macs. The application is not signed with an Apple
Developer ID and is not notarized, so Gatekeeper cannot verify its publisher
and may block the first launch.

## Choose the correct build

Open **Apple menu → About This Mac** and check the processor or chip:

- Apple M1, M2, M3, M4, or newer Apple chip: download the `aarch64` DMG;
- Intel processor: download the `x86_64` DMG.

The manual **Build macOS package** GitHub Actions workflow produces both DMGs
and a `.sha256` file for each. Download and extract the artifact matching your
Mac before continuing.

## Verify the download

From Terminal, calculate the checksum of the downloaded image:

```bash
shasum -a 256 ~/Downloads/bunch-of-keys_1.7.0_aarch64.dmg
```

Use `x86_64` in the filename on an Intel Mac. Compare the resulting hash with
the contents of the accompanying `.sha256` file. A matching checksum detects a
damaged or changed download, but because the build is unsigned it does not
prove the identity of its publisher.

## Install the application

1. Open the downloaded DMG.
2. Drag `bunch-of-keys.app` into the **Applications** folder.
3. Eject the mounted DMG.
4. Try to open `bunch-of-keys` from **Applications**.

macOS will usually refuse this first launch because the application is from an
unidentified developer. Use one of the following narrowly scoped overrides
only if you trust the source of the downloaded build.

### Recommended Gatekeeper override

1. In Finder, open **Applications**.
2. Control-click or right-click `bunch-of-keys`, then choose **Open**.
3. Confirm **Open** in the warning dialog.

If the dialog does not offer **Open**, first attempt a normal launch, then open
**System Settings → Privacy & Security**. Find the message that
`bunch-of-keys` was blocked and choose **Open Anyway**, then confirm the next
prompt. This exception applies to this application rather than disabling
Gatekeeper for the whole Mac.

### Terminal override

If the Finder and System Settings methods are unavailable, remove the
quarantine attribute from this application only:

```bash
xattr -dr com.apple.quarantine "/Applications/bunch-of-keys.app"
open "/Applications/bunch-of-keys.app"
```

Check the application path carefully before running the command. Do not use
`sudo spctl --master-disable` or otherwise disable Gatekeeper globally; that
would reduce protection for every application on the Mac.

## First launch and updates

The application appears in the menu bar and keeps running there when its
window is closed. Use the tray menu's **Quit** action to exit completely.
Enabling **Launch at sign-in** creates the normal per-user macOS autostart
entry.

To update, quit the application, install the newer `.app` over the existing
copy in **Applications**, and repeat the per-application Gatekeeper override
if macOS asks. Vault data is stored separately under:

```text
~/Library/Application Support/bunch-of-keys/
```

Replacing the application does not remove that directory. Back it up before a
manual migration or system reinstall; there is no password-recovery service.

## Uninstall

Quit `bunch-of-keys` and move `/Applications/bunch-of-keys.app` to the Trash.
If **Launch at sign-in** was enabled, disable it in the application before
removing the app. Vaults remain in the Application Support directory shown
above and must be removed separately only if you intentionally want to delete
them.
