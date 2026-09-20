# bunch-of-keys

`bunch-of-keys` is a Linux-first desktop application for keeping small,
structured collections of credentials encrypted on the local machine. The
current release is **1.1.7**.

The application is intentionally local-only. It does not provide cloud sync,
password recovery, telemetry, or a remote web interface.

## Features

- Multiple independent local vaults protected by separate master passwords.
- A recursive tree of groups and credential entries.
- Inline creation and editing without separate group or entry dialogs.
- Direct drag-and-drop for moving and reordering groups and entries.
- Dragging an unsaved group or entry draft into its intended group before it is
  saved.
- Reorderable fields with `Text`, `Secret`, and `URL` types.
- Per-field masking, explicit reveal controls, and click-to-copy values.
- Search across group names, entry names, field labels, and non-masked values.
- YAML import with automatic secret and URL detection.
- Configurable inactivity locking, clipboard clearing, and autostart.
- Automatic locking on supported Linux screen-lock and suspend signals.
- Light and dark themes, tray operation, and a compact frameless window.
- Debian package output.

All group names, entry names, field labels, and values are encrypted. The local
registry exposes only vault IDs, user-chosen vault display names, and
non-sensitive application settings so that a vault can be selected before it
is unlocked.

## Working with the vault tree

Entries are collapsed by default. Click an entry header to show or hide its
fields, click a displayed field value to copy it, and use the eye control to
reveal or hide a masked value.

The last group whose header or disclosure control was clicked becomes the
active group. The group is highlighted, and the Add menu in the application
header creates its next group or entry there. Clicking elsewhere in the tree,
outside that group and its descendants, clears the active group so the Add menu
targets the vault root again. A group's own Add menu always targets that group.

Only one inline draft or editor can be open at a time. Before saving a new
group or entry, drag its header onto another group or the root to change its
destination. Saved nodes can be dropped before or after another node, inside a
group, or at the root. Moving a group into itself or one of its descendants is
rejected.

Entry fields can be reordered by dragging their grip controls while the entry
is being edited. `Secret` fields are masked; `URL` and `Text` fields remain
visible. Vaults created by older versions remain compatible: the retired
`Note` field type is loaded as `Text` without changing its label or value.

## Window and tray behavior

The unlocked vault workspace opens at the application's minimum size of
440 × 480 logical pixels and can be resized up. At narrow widths the search
field moves below the title-bar actions, while the in-app minimize and
hide-to-tray controls remain available. Setup and unlock views size themselves
to their content.

Closing the window hides it instead of quitting. A left click on the tray icon
shows and focuses the main window. The tray menu provides `Open
bunch-of-keys`, `Lock vault`, and `Quit` actions.

## Settings

The settings dialog controls:

- launch at sign-in;
- automatic locking after 1, 5, 15, or 60 minutes of inactivity;
- clipboard clearing after 10, 30, 60, or 120 seconds;
- YAML import into the vault root.

Clipboard clearing is conditional: the application clears the clipboard only
if it still contains the value copied by `bunch-of-keys`.

## Security design

Each vault has a random 256-bit data-encryption key. The master password is
processed with Argon2id and a random salt to derive a key-encryption key. That
derived key wraps the random vault key with XChaCha20-Poly1305. The vault key
then encrypts the serialized tree with a fresh nonce on every save.

There is no separately stored password hash. An incorrect password is detected
when authenticated decryption of the wrapped vault key fails. Masked values
are withheld from the webview until explicitly revealed; copying any field is
performed by the Rust backend.

See [the architecture overview](docs/ARCHITECTURE.md) and
[the security policy](SECURITY.md) for the complete model.

## Data locations

On Linux, the application follows the XDG base directory specification:

```text
$XDG_CONFIG_HOME/bunch-of-keys/config.json
$XDG_DATA_HOME/bunch-of-keys/vaults/<uuid>.bok
```

When those variables are not set, the conventional `~/.config` and
`~/.local/share` locations are used.

## YAML import

A mapping containing only scalar values becomes an entry. A mapping containing
nested mappings becomes a group. If a mapping contains both, its scalar fields
are placed in an entry named `General` inside that group. Root-level scalar
values are also placed in a root `General` entry.

Field names containing words such as `password`, `token`, `secret`, or
`api-key` are imported as masked `Secret` fields. Labels containing `url` or
`addr` are imported as `URL` fields when their values start with `http://` or
`https://`; other values, including multiline values, become `Text` fields.
The importer reads the selected file in the webview and sends its contents
directly to the backend; it does not create an intermediate copy on disk.

## Development

The project requires Rust 1.85 or newer. On Debian or Ubuntu, install the
desktop build dependencies with:

```bash
sudo apt install build-essential curl file libappindicator3-dev \
  libgtk-3-dev librsvg2-dev libssl-dev libwebkit2gtk-4.1-dev
```

Run the same Rust checks used by CI:

```bash
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
```

The UI regression tests use Node.js' built-in test runner:

```bash
node --test ui/*.test.mjs
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

## SSH keys

Private-key support is not implemented in 1.1.7. The proposed design uses a
short-lived, embedded SSH agent so a private key does not have to be
materialized as a normal file. See [the proposed v2 SSH key design](docs/SSH_KEYS_V2.md).
