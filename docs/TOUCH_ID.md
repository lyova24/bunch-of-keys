# Touch ID design and verification

Keepy 2.2.2 adds optional, local, per-vault biometric unlocking. Master-password
access remains available in every build. Vault files and registry formats are
unchanged; biometric enrollment is not part of backups or cloud synchronization.

## Design

The native app owns Keychain and LocalAuthentication operations. The Rust service
owns password verification and vault decryption. They communicate only over the
existing inherited pipes. There is no externally accessible unlock endpoint.

Enrollment requires an unlocked matching vault and a fresh verification of its
current on-disk master password. The service returns a dedicated version-1
credential containing the vault UUID, a binding to its public password-wrapping
metadata, and the 32-byte Argon2id-derived wrapping key (base64 for transport).
The password itself and decrypted data key are never exported for enrollment.
The credential is not included in bootstrap, tree, or ordinary view payloads.
Rust credential strings, request/response wire buffers and response JSON values
are cleared on drop; Swift clears transient Data buffers where practical.
Allocator/framework copies and Swift strings remain best-effort, as with other
explicit secret operations.

The native app stores this credential as a generic-password item in the
**Data Protection Keychain**, with `biometryCurrentSet`,
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, and synchronization disabled.
Service name includes the app bundle identifier; account is the vault UUID.
The non-secret binding is stored in item attributes so status checks do not
retrieve key material or prompt for authentication. No enrollment flags or keys
are stored in config.json or UserDefaults.

After adding the item, enrollment must successfully read it through its ACL.
Cancellation/failure removes the newly added item. This verifies actual Keychain
protection, rather than trusting a standalone biometric dialog. Every unlock
uses a new LAContext, zero authentication reuse, and a biometric-only item ACL.
There is no user-presence/device-password or file-based Keychain fallback.

Before authentication, the service issues a random one-use ticket bound to a
vault, valid for 60 seconds. Completing it requires the protected credential;
matching a ticket alone grants no access. Lock, password authentication, vault
switch and service restart invalidate pending requests. Native cancellation
invalidates the LAContext; generation checks independently reject late success.
Backend locking serializes with final session installation.

Ordinary payload edits and name changes preserve the wrapping binding. Password
changes must use fresh salt/wrapping as specified in #49: an old wrapping key then
fails and the binding changes. Status refresh before use/after password unlock
removes mismatched enrollment; the user explicitly enrolls again. No #49 password
management UI is introduced by this issue. Biometric enrollment changes invalidate
the Keychain item through its ACL. Missing/stale items never prevent password
unlock. A wrapping key still grants access to old copies using that same wrapping.

## Signing and distribution

Apple's [TN3137](https://developer.apple.com/documentation/Technotes/tn3137-on-mac-keychains)
explains why biometric protection requires the Data Protection Keychain and
profile-authorized entitlements. A default ad-hoc build lacks these rights.
Keepy deliberately reports Touch ID as unavailable there, without weakening the
ACL or fabricating an access group. A development self-signature alone is not
sufficient.

For a provisioned build, obtain an explicit macOS profile for
`<TEAM>.dev.keepy.desktop` permitting its private Keychain access group, then run:

```sh
KEEPY_SIGN_IDENTITY='Developer ID Application: YOUR NAME (TEAM)' \
KEEPY_PROVISIONING_PROFILE=/absolute/path/Keepy.provisionprofile \
bash scripts/build-macos.sh
```

The script validates profile expiry, exact app identity, and allowed Keychain
group, embeds the original profile, and signs with the private app/group
entitlements. macOS validates the profile and signer when accessing the Keychain.
Use the same Team ID, app ID and group for both architectures and future updates.
A change of identity/profile permissions may make old items inaccessible: unlock
with the password and re-enroll in a correctly provisioned build. Do not add the
Rust helper to this access group; only the native app reads protected items.

See Apple's [biometric Keychain example](https://developer.apple.com/documentation/localauthentication/accessing-keychain-items-with-face-id-or-touch-id),
[current-set constraint](https://developer.apple.com/documentation/security/secaccesscontrolcreateflags/biometrycurrentset),
and [Keychain access groups](https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps).

## Verification

`cargo test --locked` covers password verification, vault binding, malformed keys,
payload preservation, password rewrapping, ticket expiry/consumption, lock/switch,
and restart. `bash scripts/test-native.sh` includes a mock Keychain for enrollment,
disable, cancellation/failure, unavailable hardware, restart, stale enrollment,
and successful authentication arriving after lock or switch. Mock tests do not
establish hardware, ACL, or signing behavior.

Before distributing a provisioned build, use synthetic vaults and verify on real
Touch ID hardware for each supported architecture:

1. Enable with the correct password; reject a wrong password and cancel the
   native prompt. Confirm cancelled setup leaves no enrollment.
2. Lock and unlock repeatedly. Each attempt must request fresh Touch ID, preserve
   masked fields, and leave the clipboard untouched. Cancel/reject a prompt and
   unlock with the password instead.
3. Switch vault, lock/sleep, or quit during authentication. A late reply must not
   open a vault. Verify inactivity and display/session locks still apply.
4. Restart and update the packaged app with the same signing identity/profile;
   confirm protected retrieval still works. Verify an ad-hoc build shows the
   unavailable state and still accepts the master password.
5. Rename a synthetic vault without changing its UUID, then test enrollment.
   Rewrap its password and confirm the old enrollment no longer opens it.
6. Add/remove an enrolled fingerprint; confirm password fallback and re-enrollment.
   Disable enrollment and verify the protected item is removed.

Real Touch ID, profile-authorized Keychain reads, and signed update continuity
require a provisioned build and human biometric interaction. Do not report mock
or ad-hoc tests as completing those hardware checks.
