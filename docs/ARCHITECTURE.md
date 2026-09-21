# Architecture

This document describes the architecture implemented in `bunch-of-keys`
1.5.0.

## Components

```text
┌────────────────────────────────────────────┐
│ Tauri window and tray                      │
│ static HTML/CSS/JS, no remote content      │
└──────────────────────┬─────────────────────┘
                       │ narrow IPC commands
┌──────────────────────▼─────────────────────┐
│ Linux application service                  │
│ sessions, clipboard, URL/SSH launch, D-Bus │
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

The `src/core/` module has no dependency on Tauri or Linux APIs. It owns the
tree model, validation, YAML conversion, and encrypted envelope. This keeps the
on-disk format independently testable and leaves room for a future CLI while
retaining a single-crate repository layout.

`src/app.rs` owns the unlocked session and exposes a small set of Tauri
commands. `src/view.rs` converts the encrypted model into the webview-facing
representation. `src/storage.rs` owns the application registry and atomic file
I/O. `src/system_monitor.rs` listens for supported screen-lock and suspend
signals.

## Multiple vaults and sessions

The application registry stores a list of vault UUIDs, display names, and
filenames, plus non-sensitive application settings. Vault display names are
deliberately treated as non-secret because the user must choose a vault before
supplying its password. Everything below a vault—including group names, entry
names, field labels, and values—is encrypted.

Only one vault is unlocked in a process at a time. Unlocking or creating a
vault installs an in-memory `Session`; locking drops it and notifies the UI.
Closing the window only hides it, so it does not lock the session by itself.
The inactivity timer, supported screen-lock signals, supported suspend signals,
the UI lock action, and the tray lock action all use the same lock path.

## Vault tree and field model

The encrypted payload contains a recursive list of two node variants:

```text
Node
├── Group { id, name, children[] }
└── Entry { id, name, fields[] }
```

Each field has a stable UUID, label, value, kind, and masking flag. Current
field kinds are `text`, `secret`, `url`, and `ssh`. SSH fields store structured
connection data and a reference to a reusable named private key in the
encrypted vault. The deserializer accepts the retired `note` kind as `text`,
which preserves existing vaults without a data migration.

Tree moves specify the node UUID, target parent group (or the root), and target
index. The model rejects missing targets, invalid positions, and cyclic group
moves. Field order is the order stored in each entry's field list.

## UI state and editing

The frontend is static HTML, CSS, and JavaScript under `ui/`; it does not use a
remote runtime or load remote content. The Rust `VaultView` sent to the webview
contains full values only for non-masked fields. Masked values are represented
by their ID, label, kind, and mask state until an explicit reveal command is
made.

Expansion state, search text, the active group, keyboard tree selection,
revealed values, and unsaved drafts are ephemeral frontend state. They are
cleared when the vault locks or the user switches sessions.

The visible vault hierarchy is exposed as an accessible tree with one roving
tab stop. Group headers, entry headers, and fields in expanded entries share a
single visual-order navigation sequence. Arrow keys move and expand or collapse
the selection; Enter toggles nodes or dispatches the selected field action.
Keyboard selection is restored across DOM re-renders and cleared on pointer
input.

The selected appearance mode is the exception: `system`, `light`, or `dark` is
stored in webview local storage. The resolved light or dark appearance is kept
separate from that preference. A `prefers-color-scheme` listener updates every
surface immediately while System mode is active and becomes a no-op in either
explicit mode. Legacy stored `light` and `dark` values remain valid explicit
preferences.

Only one inline draft or editor is allowed at a time. A new group or entry
draft initially belongs to the selected parent, but remains a DOM-only object
until save. Dragging the draft changes its `parentId` and displayed path; the
backend receives only the final parent when the draft is saved. This prevents
temporary nodes from being written to the encrypted vault.

The last clicked or expanded group is the active group. The header Add menu
uses it as the default parent. A click elsewhere in the tree, outside the
active group and its descendants, restores the root as the default parent.
This selection is visual UI state and is never persisted.

Saved-node drag-and-drop calls `move_node`, which performs a normal
transactional mutation. Field drag-and-drop changes editor row order, and that
order is persisted when the entry is saved. Custom drag images copy only the
node header, remain translucent, and are scaled to 105% of the source header
after compensating for the display scale.

## Window and desktop integration

The main Tauri window is transparent and undecorated. The visible rounded
surface, its shadow, and the resize handles are implemented in CSS so resizing
tracks the visible edge instead of an invisible native shadow. The vault view
opens at the configured 440 × 480 logical-pixel minimum; setup and unlock views
measure their content before resizing.

The wide header places a capped-width search box between the vault identity and
the application actions. At compact widths search moves onto its own row, while
the minimize and hide-to-tray controls remain visible.

The tray exposes Open, Lock, and Quit actions. A left click shows and focuses
the main window, and a second application launch focuses the existing instance.
Autostart launches that instance hidden and locked.

## File locations

Linux paths follow the XDG base directory specification:

```text
$XDG_CONFIG_HOME/bunch-of-keys/config.json
$XDG_DATA_HOME/bunch-of-keys/vaults/<uuid>.bok
```

If the XDG variables are absent, the conventional `~/.config` and
`~/.local/share` locations are used through the `directories` crate.

The registry and vault envelope are capped at 1 MiB and 64 MiB respectively.
Application directories use mode `0700`, and atomically written files use mode
`0600` on Unix.

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

Every persisted mutation is applied to a cloned in-memory tree. The backend
validates the result, encrypts a new envelope with a fresh payload nonce, and
writes it to a temporary file in the same directory. The file is synced and
atomically renamed over the destination. Only after a successful write does
the active session adopt the new tree.

The same mutation path is used for adding, editing, renaming, deleting,
moving, reordering, and importing nodes. A failed validation, encryption, or
write leaves both the active session and the existing vault file unchanged.

## UI trust boundary

The webview receives non-masked values needed for display and search. Masked
values are excluded from that view, so their contents are not searchable in
the frontend. Revealing a masked field returns its value explicitly. Copying
any field happens in Rust from its entry and field IDs without returning the
copied value to JavaScript.

The UI loads local assets only. The content security policy permits only local
scripts, styles, and images plus Tauri IPC. Tauri capabilities expose only the
application's own commands and the minimal core APIs required for events and
window interaction.
