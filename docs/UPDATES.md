# In-app updates

Keepy 2.2 and later uses [Sparkle 2](https://sparkle-project.org/documentation/)
on macOS 14 and later. Choose **Keepy → Check for Updates…** to compare your
installed version with the newest compatible release and read its release notes.
Choose **Install Update**, then approve **Install and Relaunch** after downloading.
The standard Sparkle window shows download progress and check, network, download,
verification and installation errors. Cancel a download or retry a failed check
from the same menu. An interrupted download leaves the installed app intact.

**Settings → Updates → Automatically check for updates** controls background
checks immediately and is retained across launches. Manual checks remain
available when automatic checks are disabled. Downloads and installation always
require approval; silent installation and system profiling are disabled.

An open editor, SSH key window or unsaved Settings triggers a confirmation
before termination. Choose **Keep Editing** to save first, or explicitly discard
the draft. Quit/restart is refused while a save is in progress. Before exiting,
Keepy locks the vault, clears secrets and owned clipboard contents, and shuts
down its service. The updated app starts locked and uses the same encrypted
vaults, settings, identity and master password.

## Release publishing

The updater uses separate signed `appcast-arm64.xml` and `appcast-x86_64.xml`
assets from the latest GitHub Release. Each feed contains matching binaries;
Sparkle also enforces the minimum OS version and refuses downgrades. DMGs remain
available for initial installation and recovery. Install into `/Applications`
before updating rather than running from a read-only disk image.

Sparkle is pinned at 2.10.0. `scripts/fetch-sparkle.sh` verifies the distribution
archive's SHA-256 before extracting it. Retain the upstream license in the
embedded framework. Update this pin and checksum together when upgrading.

Create the production Ed25519 signing key once, with permission from the owner:

```sh
bash scripts/fetch-sparkle.sh
target/sparkle/bin/generate_keys --account keepy
```

The private key stays in the login Keychain. Put only its printed public key in
`SUPublicEDKey` in `macos/Info.plist`. Back up the private key securely. Export
it with `generate_keys --account keepy -x <private-file>` and configure its
contents as the repository Actions secret `KEEPY_UPDATE_PRIVATE_KEY`. Never
commit the private key or expose it in logs. Losing this key prevents updates
to existing ad-hoc installations; replacing the public key requires a planned
key rotation or a manual reinstall.

For a local signed release, build both architectures and run for each:

```sh
KEEPY_ARCH=arm64 bash scripts/build-macos.sh --dmg
KEEPY_ARCH=arm64 bash scripts/package-update.sh
```

Repeat with `x86_64` after installing the matching Rust target. The packaging
script uses the Keychain account `keepy`, or `KEEPY_UPDATE_KEY_FILE` in CI. It
creates ZIP update archives, checksum files and signed feeds with embedded notes
from the current changelog entry. Publish both architectures together. Feed URLs
point at immutable versioned release assets; never overwrite a published ZIP.
Before copying artifacts into `dist`, the packager checks metadata, Mach-O
architecture and both signatures against the public key embedded in the app.

Pushing a `vX.Y.Z` tag runs `.github/workflows/release.yml`. The workflow checks
the tag matches all version files, builds both architectures, signs archives and
feeds with the secret, and uploads everything to a draft release. Only after
both builds succeed does it publish that release as latest. Workflow dispatch
can publish an existing version tag. It does not close issues.

## Signing and verification

All updates, including ad-hoc development releases, require Ed25519 signatures.
Both the feed and the archive are authenticated, and archives are verified
before extraction. A build without a valid public key disables updates with an
explanation in Settings. Isolated `KEEPY_DATA_DIR` runs never start the updater.

Ad-hoc signing is not Developer ID signing or notarization: it does not establish
an Apple-verified publisher identity. The first installation still requires the
documented Gatekeeper procedure. Update authentication relies on the public key
trusted in that first installation. Sparkle's own binaries retain their upstream
signature in ad-hoc bundles. Because an ad-hoc app has no Team ID, its hardened
runtime signature includes `disable-library-validation` so it can load the
pinned Sparkle framework. This entitlement is applied only to ad-hoc builds;
Developer ID builds retain library validation. Update archive and feed
authentication remain enforced in either case.

For Developer ID distribution, set `KEEPY_SIGN_IDENTITY` when building. The script
signs Sparkle's nested helpers inside-out and the app last. Notarize and staple
the app **before** creating the update ZIP; notarize DMGs separately. The current
release workflow intentionally produces ad-hoc builds and does not configure
Apple credentials. Ed25519 signatures remain mandatory for either mode.

Run `scripts/test-updates.sh` to verify real Sparkle signature acceptance and
rejection of tampered and truncated packages. Native tests exercise Sparkle's
version comparator, architecture feed routing and restart guards. Headless
transport checks use signed test feeds and an isolated bundle to verify manual
checks with automatic checks disabled, older releases, OS requirements, invalid
feeds and offline failures. Release verification should additionally cover an
actual install/relaunch and cancellation mid-download using an
isolated test installation. Visual testing was explicitly waived for #43/#46.
