# bunch-of-keys

A native macOS application for local, encrypted credential collections.
Current version: **2.0.1**. Requires **macOS 14 Sonoma or later**.

The interface uses SwiftUI and AppKit: a standard Mac window, a compact tree with
keyboard navigation and drag-and-drop, native menus, file panels, and Settings.
Optional **Liquid Glass** adds native glass surfaces and a translucent background
across the entire window on macOS 26 and later.
System, Light, and Dark appearance remain available on every supported Mac.

There is no cloud sync, telemetry, account requirement, or password recovery.
Linux and Windows are no longer supported.

## Features

- Multiple independent vaults with separate master passwords.
- Recursive groups and entries; direct tree and field drag-and-drop; search
  through names, labels, and visible values without searching masked secrets.
- macOS-style colored tags on groups and entries, with multiple tags per item
  and color filters that combine with search while retaining the tree context.
- Editable Text, Secret, URL, and structured SSH fields, stable field IDs,
  explicit masking and reveal, click-to-copy, and HTTP(S) browser actions.
- Reusable named OpenSSH keys stored inside encrypted vaults, guarded deletion,
  encrypted-key passphrase prompts, and Terminal connections through a private,
  short-lived in-memory agent. Private keys never become temporary key files.
- YAML import through the native file picker.
- Inactivity, sleep, display-sleep, and session locking; conditional clipboard
  clearing; launch at login through ServiceManagement; and menu bar operation.
- Existing 1.x macOS vaults open in place, with the same encryption and storage
  locations. Back up data before upgrading; see the installation guide.

## Install and build

Download the DMG for Apple Silicon (`arm64`) or Intel (`x86_64`), verify its
checksum, then drag the app into Applications. See
[macOS installation](docs/INSTALL_MACOS.md) for unsigned builds and updates.

For a local build, install Rust stable and Xcode 26 or newer (including its
macOS SDK), then run:

```sh
bash scripts/build-macos.sh
open target/macos/$(uname -m)/bunch-of-keys.app
```

The Swift source also has a Swift Package manifest for opening in Xcode. The
packaged application embeds the Rust service alongside the native executable.

## Documentation

- [User guide](docs/USER_GUIDE.md)
- [Development and packaging](docs/DEVELOPMENT.md)
- [Architecture](docs/ARCHITECTURE.md)
- [SSH keys](docs/SSH_KEYS_V2.md)
- [Security policy](SECURITY.md)
- [Changelog](CHANGELOG.md)
