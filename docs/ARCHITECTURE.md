# Architecture

Version 2.1.0 is macOS-only. The presentation layer is SwiftUI/AppKit, built
against the macOS SDK with a macOS 14 deployment target. There is no webview,
HTML/JavaScript frontend, or Tauri runtime.

## Components

```text
SwiftUI application + AppKit outline + native system integrations
                    │ private inherited stdin/stdout pipes
Rust service: src/protocol.rs → src/app.rs
                    │ transactional operations
src/core: model, validation, YAML import, Argon2id/XChaCha20-Poly1305
                    │ atomic writes
config.json + vaults/<uuid>.bok
```

The Keepy app bundle contains `Contents/MacOS/bunch-of-keys` (Swift) and
`Contents/MacOS/bunch-of-keys-core` (Rust). The core starts once per application
process. JSON requests and responses are newline framed with request IDs,
serialized on a dedicated queue, and bounded to 72 MiB. No localhost server or
persistent IPC socket is exposed. Secret arguments are sent over pipes, never
command-line arguments. EOF locks and exits the service; a crashed service
clears the native UI and reports an error. Reopening the app starts it again.

An exclusive file lock prevents simultaneous service writers for the same data
directory; macOS app launches activate an existing instance. CoreClient handles
transport; AppStore publishes the masked view, selection, editor state, settings,
and active connections. A generation counter rejects late responses after
locking. SwiftUI uses one native outline for groups, entries, fields and inline
editors, forms, commands, Settings and MenuBarExtra. AppKit's NSOutlineView supplies native
hierarchical keyboard navigation, selection, context menus, and direct moves.
Search and tag filters disable ordering operations because filtered indices are
ambiguous.
Field editors use direct drag-and-drop and preserve stable field identities.

Groups and entries carry a validated set of seven color tags in the encrypted
payload and masked view. Tags default to empty when decoding older vaults.
The native tree combines an OR across selected colors with text search; tag
matches on a group include descendants, and ancestors of matching items remain
visible. Filters are temporary session state and clear on lock or vault change.

Only one vault can be unlocked at a time. Model changes clone the current data,
validate, encrypt, atomically persist, and then commit the in-memory update.
Names, fields, tags, and SSH key documents remain encrypted. Ordinary view
responses contain no masked values or private key documents. Explicit reveal,
edit and copy actions request field values separately. The native pasteboard clears only
while its change counter still matches the app's write. Locking clears pending
clipboard data owned by the app as well as reveals, drafts, and active agents.

A backend watchdog enforces inactivity independently of the native UI's polling.
Local AppKit input updates activity. NSWorkspace sleep, display-sleep and session
notifications, plus the distributed screen-lock notification, trigger locking.
The app remains available in the menu bar after closing the main window. Quit
first requests a lock, then closes the pipe and waits for graceful service exit.

Settings live in the existing registry, including appearance and Liquid Glass.
ServiceManagement's SMAppService controls launch at login. On macOS 26+, the
Liquid Glass preference combines SwiftUI glassEffect surfaces with a native
NSVisualEffectView using behind-window blending across the main and Settings
windows. The window and title-bar backgrounds are transparent; the native
material stays below the SwiftUI content and resizes with the window. Disabling
the preference or enabling Reduce Transparency restores an opaque background.
Standard Mac controls follow the operating system's appearance.

## Compatibility and storage

The envelope and encrypted payload formats are unchanged. Existing macOS 1.x
registry and vault files are discovered in:

```text
~/Library/Application Support/bunch-of-keys/config.json
~/Library/Application Support/bunch-of-keys/vaults/<uuid>.bok
```

New preference keys deserialize with defaults when opening older registries.
Legacy Note fields continue to decode as Text, and schema v1 data keeps its
existing field identities during the existing v2 SSH-schema migration.
Application directories have mode 0700 and vault files mode 0600. Atomic writes
use an exclusive temporary file, sync, rename, and directory sync.

For development and automated tests only, BUNCH_OF_KEYS_DATA_DIR redirects both
registry and vault storage. Testing uses synthetic vaults in temporary folders.
SSH agents use private per-connection temporary directories, with a short /tmp
fallback for Darwin's Unix socket path limit. See SSH_KEYS_V2.md for details.

## Branding

`AppLogo.swift` defines the Keepy bunch of keys as a vector composition. The
menu-bar template and SwiftUI branding reuse that composition. The geometric
wordmark outlines and green/blue palette are defined in the same file.
`render-logo.swift` exports `icons/logo.svg`, `icons/wordmark.svg` and the
1024-pixel `icons/icon.png`; packaging renders the same source before generating
all ICNS representations. Stock folder,
entry, field and action symbols retain their functional meaning.

The public app and disk-image names are Keepy. The bundle identifier, service
executable and storage/encryption identifiers keep their existing values so
updates discover and unlock existing data in place.
