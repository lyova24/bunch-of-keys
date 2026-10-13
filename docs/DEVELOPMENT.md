# Development and packaging

## Requirements

- macOS 14+ on Apple Silicon or Intel.
- Xcode 26+ or Command Line Tools containing a macOS 26+ SDK and Swift 6.
- Rust 1.89+ (stable) with rustfmt and Clippy; Python 3 for icon packaging.

The UI uses SwiftUI, AppKit, ServiceManagement and UniformTypeIdentifiers.
The Rust service keeps the audited encryption and OpenSSH-agent implementation.
No Node, Tauri CLI, GTK, D-Bus or WebKit dependencies are needed.

## Build and run

```sh
bash scripts/build-macos.sh
open target/macos/$(uname -m)/bunch-of-keys.app
```

Open macos/Package.swift in Xcode to navigate and compile the Swift executable.
For a complete runnable bundle with its Rust service, use the packaging script.
The build uses the SDK selected by xcrun, or an explicit SDKROOT override, with a
macOS 14 deployment target. When multiple SDK generations are installed, ensure
the selected SDK matches your compiler and linker.

For an isolated manual run without touching your real vaults:

```sh
BUNCH_OF_KEYS_DATA_DIR=/tmp/bok-development \
  target/macos/$(uname -m)/bunch-of-keys.app/Contents/MacOS/bunch-of-keys
```

## Checks

```sh
bash scripts/check-version-sync.sh
cargo fmt --all -- --check
cargo clippy --locked --all-targets -- -D warnings
cargo test --locked
bash scripts/build-macos.sh
bash scripts/test-native.sh
```

Rust tests cover encryption, model validation, compatibility, storage and SSH
agent cleanup. Swift integration tests exercise the actual bundled pipe service,
masking, copying, URLs, field reordering, tree moves, colored tag mutations,
legacy decoding and filtering, YAML import, SSH key references, preferences,
and persistence after a full process restart. Native store tests verify tag
filter cleanup, clipboard ownership, clearing on lock, and protection from
late reveal responses on a private test pasteboard.
Visually verify native windows, editing, drag-and-drop, lock/unlock, Settings,
appearance and Liquid Glass using synthetic data before shipping UI changes.

## Packaging

```sh
bash scripts/build-macos.sh --dmg
```

The result is `dist/bunch-of-keys_2.0.1_<arch>.dmg` plus its SHA-256 checksum.
Set BOK_ARCH=arm64 or BOK_ARCH=x86_64 to cross-build another architecture after
installing the matching Rust target with rustup. The script signs locally with
an ad-hoc identity by default. Set BOK_SIGN_IDENTITY to a Developer ID identity
for distribution signing. Notarization is a separate release step and requires
Apple developer credentials; ad-hoc builds are not notarized.

The manual GitHub package workflow accepts a branch/tag/commit and builds both
architectures on macOS 26. CI also checks both native bundles, Rust and Swift.
The Intel bundle is cross-compiled on Apple Silicon; interactive runtime checks
on Intel hardware remain part of release verification. Security checks run on
macOS and use cargo-deny and cargo-audit. No workflow publishes releases,
creates tags, or closes GitHub issues automatically.

Version synchronization covers Cargo.toml, the root Cargo.lock package,
macos/Info.plist (both bundle versions), and the latest changelog entry.
