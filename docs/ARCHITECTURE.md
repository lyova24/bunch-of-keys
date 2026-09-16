# Architecture

## Components

```text
┌────────────────────────────────────────────┐
│ Tauri window and tray                      │
│ static HTML/CSS/JS, no remote content      │
└──────────────────────┬─────────────────────┘
                       │ narrow IPC commands
┌──────────────────────▼─────────────────────┐
│ Linux application service                  │
│ sessions, clipboard, autostart, D-Bus      │
└──────────────────────┬─────────────────────┘
                       │ typed Rust API
┌──────────────────────▼─────────────────────┐
│ src/core                                   │
│ tree model, YAML import, envelope crypto   │
└──────────────────────┬─────────────────────┘
                       │ atomic file writes
┌──────────────────────▼─────────────────────┐
│ config.json + vaults/<uuid>.bok            │
└────────────────────────────────────────────┘
```

The `src/core/` module has no dependency on Tauri or Linux APIs. This keeps the
encrypted format testable and allows a future CLI to use the same
implementation while retaining a single-crate repository layout.

## Multiple vaults

The application registry stores a list of vault UUIDs, display names, and
filenames. Vault display names are deliberately treated as non-secret because
the user must choose a vault before supplying its password. Everything below a
vault—including group names and field labels—is encrypted.

Only one vault is unlocked in a process at a time. Switching vaults locks and
drops the current session first.

## File locations

Linux paths follow the XDG base directory specification:

```text
$XDG_CONFIG_HOME/bunch-of-keys/config.json
$XDG_DATA_HOME/bunch-of-keys/vaults/<uuid>.bok
```

If the XDG variables are absent, the conventional `~/.config` and
`~/.local/share` locations are used through the `directories` crate.

## Encrypted envelope

The `.bok` file is a versioned JSON envelope. JSON is used only for the
non-secret framing and base64 ciphertext. The encrypted payload is also
versioned and may move to a different serialization format in a future format
version.

```text
VaultEnvelope
├── magic = "BOKV"
├── format_version
├── vault_id
├── KDF parameters + salt
├── wrapped vault key
│   ├── nonce
│   └── ciphertext + authentication tag
└── encrypted payload
    ├── nonce
    └── ciphertext + authentication tag
```

The password itself is never used as a cipher key. Argon2id derives a fixed
length key-encryption key. Successful authenticated decryption of the random
vault key is the password check; a separate password verifier is not stored.

## Transactional updates

Mutations are applied to a cloned in-memory tree. A new encrypted envelope is
prepared with a fresh payload nonce and written to a temporary file in the same
directory. The file is synced and atomically renamed over the destination.
Only after a successful write does the active session adopt the new tree.

## UI trust boundary

The webview receives non-masked values needed for normal display. Masked values
are represented only by IDs and metadata. Revealing a masked field returns its
value explicitly; copying it happens in Rust without returning it to the UI.

The UI loads local assets only. Tauri capabilities expose only the application's
own commands and the minimal core event API required for lock notifications.
