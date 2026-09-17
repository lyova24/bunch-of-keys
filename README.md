# bunch-of-keys

`bunch-of-keys` is a Linux-first tray application for keeping small, structured
collections of credentials encrypted on the local machine.

The application is intentionally local-only. It does not provide cloud sync,
password recovery, telemetry, or a remote web interface.

## Current scope

- Multiple independent local vaults.
- A recursive group and entry tree.
- Arbitrary fields with per-field masking.
- Authenticated encryption at rest.
- YAML import with secret-field detection.
- Copying a field by clicking its value and clearing the clipboard after 30 seconds.
- Automatic locking after five minutes of inactivity and on Linux
  screen-lock/suspend signals.
- Tray operation and optional autostart.
- A compact frameless window with in-app controls and rounded corners.
- Debian package output.

All group names, entry names, field labels, and values are encrypted. The local
registry exposes only vault IDs, user-chosen vault display names, and
non-sensitive application settings so that a vault can be selected before it
is unlocked.

## Security design

Each vault has a random 256-bit data-encryption key. The master password is
processed with Argon2id and a random salt to derive a key-encryption key. That
derived key wraps the random vault key with XChaCha20-Poly1305. The vault key
then encrypts the serialized tree with a fresh nonce on every save.

There is no separately stored password hash. An incorrect password is detected
when authenticated decryption of the wrapped vault key fails. Changing a
password can therefore re-wrap the vault key without re-encrypting every
record.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and
[SECURITY.md](SECURITY.md) for the complete model.

## Development

Required on Debian/Ubuntu:

```bash
sudo apt install build-essential curl file libappindicator3-dev \
  libgtk-3-dev librsvg2-dev libssl-dev libwebkit2gtk-4.1-dev
```

Run the core tests:

```bash
cargo test
```

Run the desktop application:

```bash
cargo install tauri-cli --version '^2' --locked
cargo tauri dev
```

Build a Debian package:

```bash
cargo tauri build --bundles deb
```

The resulting package is written under `target/release/bundle/deb/`.

## YAML import

A mapping containing only scalar values becomes an entry. A mapping containing
nested mappings becomes a group. If a mapping contains both, its scalar fields
are placed in an entry named `General` inside that group.

Field names containing words such as `password`, `token`, `secret`, or
`api-key` are imported as masked fields. The importer never writes the source
YAML to disk.

## SSH keys

Private-key support is intentionally deferred. The proposed v2 design uses a
short-lived, embedded SSH agent so a private key never has to be materialized
as a normal file. See [docs/SSH_KEYS_V2.md](docs/SSH_KEYS_V2.md).
