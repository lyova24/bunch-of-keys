# Development and packaging

## Requirements

- Build host: macOS 26.6+ with Xcode 27.0 or matching Command Line Tools 27.
  The application still runs on macOS 14+ on Apple Silicon or Intel.
- macOS SDK 27.x, Apple Swift 6.4 and the Clang/linker shipped with that
  Xcode/CLT release. SDK 27 alone with CLT 26 tools is unsupported.
- Rust 1.89+ (stable) with rustfmt and Clippy; Python 3 for icon packaging.

The UI uses SwiftUI, AppKit, ServiceManagement and UniformTypeIdentifiers.
The Rust service keeps the audited encryption and OpenSSH-agent implementation.
No Node, Tauri CLI, GTK, D-Bus or WebKit dependencies are needed to build the
application. The documentation site separately uses Node.js and Diplodoc;
see [Documentation and screenshots](DOCUMENTATION.md).

## Build and run

```sh
# Explicit full-Xcode selection (no global xcode-select change required):
export DEVELOPER_DIR=/Applications/Xcode_27.0.app/Contents/Developer
python3 scripts/check-macos-toolchain.py
bash scripts/build-macos.sh
open target/macos/$(uname -m)/Keepy.app
```

Open macos/Package.swift in Xcode to navigate and compile the Swift executable.
For a complete runnable bundle with its Rust service, use the packaging script.
Every build/test/package entry point uses `scripts/macos-toolchain.sh`. It
prefers `/Applications/Xcode_27.0.app` (or `Xcode_27.app`) when installed;
otherwise it verifies the developer directory selected by `xcode-select`.
An explicit `DEVELOPER_DIR` always wins. For Command Line Tools 27, use:

```sh
export DEVELOPER_DIR=/Library/Developer/CommandLineTools
bash scripts/build-macos.sh
```

The default SDK is explicitly `macosx27.0`, not the moving `macosx` alias. An
explicit absolute `SDKROOT` can select another compatible macOS 27.x SDK.
Unset stale SDKROOT values from older development shells. Swift, Clang and ld
must resolve inside the selected Apple developer directory. Checks report paths
and versions, then compile/link SwiftUI and libiconv probes for **both** CPU
architectures; this catches unsupported Swift interfaces and old TAPI/linkers
before compiling the project. Successful probes are cached by tools, SDK and
checker fingerprint; `python3 scripts/check-macos-toolchain.py --fresh` repeats
those probes. Swift module caches are isolated by the selected tools/SDK fingerprint.

Cargo uses a linker wrapper that passes the selected SDK and Apple linker
explicitly, plus `MACOSX_DEPLOYMENT_TARGET=14.0`. Swift app, native tests and host
helpers use explicit macOS 14 targets. `scripts/verify-macos-build.py` checks the
bundle's minimum OS and the SDK/minimum OS in both own Mach-O executables and
the update verifier. No SDK/compiler check is bypassed by an override.

SDK 27 exports a `State` macro in addition to the existing SwiftUI property
wrapper. The matching CLT package does not include the SwiftUIMacros plugin.
`ViewState<Value>` explicitly aliases `SwiftUI.State<Value>` throughout Keepy,
preserving property-wrapper semantics and macOS 14 compatibility with both CLT
and full Xcode. The early Swift probe covers this form too.

Apple documents SDK 27's supported build hosts and deployment targets in the
[Xcode requirements](https://developer.apple.com/xcode/system-requirements).


For an isolated manual run without touching your real vaults:

```sh
KEEPY_DATA_DIR=/tmp/bok-development \
  target/macos/$(uname -m)/Keepy.app/Contents/MacOS/keepy
```

## Checks

```sh
bash scripts/check-version-sync.sh
python3 scripts/test-macos-toolchain.py
bash scripts/with-macos-toolchain.sh cargo fmt --all -- --check
bash scripts/with-macos-toolchain.sh cargo clippy --locked --all-targets -- -D warnings
bash scripts/with-macos-toolchain.sh cargo test --locked
bash scripts/build-macos.sh
bash scripts/test-native.sh
```

Rust tests cover encryption, model validation, compatibility, storage and SSH
agent cleanup. Swift integration tests exercise the actual bundled pipe service,
masking, copying, URLs, field reordering, tree moves, colored tag mutations,
legacy decoding and filtering, YAML import, SSH key references, preferences,
vault renaming and master password changes, and persistence after a full process
restart. Vault management tests also cover failed writes, old-password rejection,
Touch ID invalidation and late responses after locking. Tray tests cover encrypted
per-vault preferences, inherited and field tags, deduplication, copy/URL/SSH actions,
editor guards, live menu refresh and empty/locked states. Native store tests verify tag
filter cleanup, clipboard ownership, clearing on lock, and protection from
late reveal responses on a private test pasteboard.
Visually verify native windows, editing, drag-and-drop, lock/unlock, Settings,
appearance and Liquid Glass using synthetic data before shipping UI changes.

## SDK 27 verification record

Verified on 2026-10-17 with macOS 26.7.1, Command Line Tools 27.0,
Apple Swift 6.4 (`swiftlang-6.4.0.34.1`), Clang `2100.3.34.2`, linker
`27037.1`, and SDK 27.0. Both arm64 and x86_64 bundles and recovery DMGs built;
code signatures, Mach-O SDK/minimum OS, DMG checksums, bundle launch (Intel via
Rosetta), all 65 Rust tests, Clippy/formatting, native integration, signing-profile
checks and update signature/transport tests passed. The live arm64 smoke test
covered unlock, lock, expanded workspace, field editor, Settings and saved theme
changes with synthetic data. Shortcut conflicts with another running Keepy
were reported correctly; native registration/action tests passed separately.

No macOS 14 runtime or physical Intel Mac was available. Runtime verification on
macOS 14 and physical Intel remains a release check; Mach-O and bundle metadata
were verified to retain 14.0, and existing API availability guards were preserved.
The GitHub workflow configuration was validated locally against the published
runner inventory; remote CI execution requires pushing these changes.

## Packaging

```sh
bash scripts/build-macos.sh --dmg
```

The result is `dist/Keepy_<version>_<arch>.dmg` plus its SHA-256 checksum.
Set KEEPY_ARCH=arm64 or KEEPY_ARCH=x86_64 to cross-build another architecture after
installing the matching Rust target with rustup. The script signs locally with
an ad-hoc identity by default. Set KEEPY_SIGN_IDENTITY to a Developer ID identity
for distribution signing. Notarization is a separate release step and requires
Apple developer credentials; ad-hoc builds are not notarized.

Touch ID requires an explicit macOS provisioning profile authorizing the app's
private Keychain group. Set `KEEPY_PROVISIONING_PROFILE` to that profile and
`KEEPY_SIGN_IDENTITY` to the matching Apple signing identity. The build validates
the decoded profile, embeds it, and signs the app with its private app identifier
and Keychain group. Ad-hoc builds remain supported with password unlocking.
See [Touch ID design and verification](TOUCH_ID.md) for details and hardware checks.

The manual GitHub package workflow accepts a branch/tag/commit and builds both
architectures on the Apple Silicon `xcode-27` runner. All macOS workflows pin
`/Applications/Xcode_27.0.app/Contents/Developer` through the shared composite
action and export the verified SDK/linker settings before Cargo runs. The runner
must offer Xcode 27.0 and SDK 27.0; no fallback to `macos-26` or an older Xcode
is permitted. Availability may differ for private/enterprise runner pools: use
a provisioned runner with that toolchain if `xcode-27` is unavailable. See the
[runner image inventory](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md).
CI also checks both native bundles, Rust and Swift.
The Intel bundle is cross-compiled on Apple Silicon; interactive runtime checks
on Intel hardware remain part of release verification. Security checks run on
macOS and use cargo-deny and cargo-audit. The version-tag release workflow
publishes signed updates and recovery DMGs; see [In-app updates](UPDATES.md)
for signing setup and publishing. No workflow closes GitHub issues automatically.

Version synchronization covers Cargo.toml, the root Cargo.lock package,
macos/Info.plist (both bundle versions), and the latest changelog entry.

## Logo assets

Edit the vector shapes and palette in `macos/Sources/Keepy/AppLogo.swift`.
The packaging script renders that source on the build host before generating
the ICNS sizes. Regenerate the checked-in assets with:

```sh
source scripts/macos-toolchain.sh
mkdir -p target/swift-module-cache
"$KEEPY_SWIFTC" -swift-version 5 -warnings-as-errors -sdk "$SDKROOT" -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$KEEPY_SWIFT_MODULE_CACHE" \
  macos/Sources/Keepy/AppLogo.swift scripts/render-logo.swift \
  -o target/render-logo
target/render-logo icons
```

The menu bar uses a monochrome template to adapt to the system appearance.

Field tray-action coverage uses a private pasteboard, an injected URL opener and
an encrypted synthetic SSH key (stopping at the passphrase prompt). It verifies
field-tag editor payloads/context menus, inherited matching, Return parity,
clipboard expiry and stale menu targets without launching a browser or Terminal.

Tag-name tests cover legacy decoding, Unicode limits, collisions with default
names, encrypted persistence, vault isolation, filter/tray/assignment stability,
context-menu labels, reset, colored tray groups and live submenu renaming.
Failed-write tests temporarily replace an isolated test vault file with a
directory to force atomic-rename failure, then restore and reopen its original
encrypted bytes; no user vaults are used.
