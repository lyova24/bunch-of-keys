# User guide

This guide describes the user-facing behavior in `bunch-of-keys` 1.7.0.

For installation on Apple Silicon or Intel Macs, including the required
per-application Gatekeeper override for the unsigned build, see
[Installing on macOS](INSTALL_MACOS.md).

## Vaults

Each vault is independent and protected by its own master password. The vault
selector exposes only the vault UUID and user-chosen display name before
unlocking; group names, entry names, field labels, field values, and SSH keys
remain encrypted.

## Vault tree

Groups and entries are collapsed by default. Click a group or entry header to
show or hide its contents. Only one inline draft or editor can be open at a
time.

The last group opened through its header or disclosure control becomes the
active group. The header Add menu creates its next group or entry there.
Collapsing the active group or one of its ancestors clears that target, as does
a click elsewhere in the tree outside the group and its descendants. After it
is cleared, the header Add menu targets the vault root. A group's own Add menu
always targets that group.

Before saving a new group or entry, drag its header onto another group or the
root to change its destination. Saved nodes can be dropped before or after
another node, inside a group, or at the root. Moving a group into itself or one
of its descendants is rejected.

Entry fields can be reordered by dragging their grip controls while the entry
is being edited. Vaults created by older versions remain compatible: the
retired `Note` field type loads as `Text` without changing its label or value.

Every hierarchy level uses the same horizontal step. Entry cards are indented
as containers alongside nested groups, and their credential containers use one
matching additional step.

## Keyboard navigation

The tree exposes a single keyboard selection across visible groups, entries,
and fields inside expanded entries. The current tree item receives focus as
soon as an unlocked vault opens, so navigation does not require an initial
mouse click:

- `ArrowUp` and `ArrowDown` move in visual order;
- `ArrowRight` expands the selected group or entry;
- `ArrowLeft` collapses an expanded group or entry; from child content or an
  already-collapsed item it first moves to the containing entry or group, so a
  repeated press can collapse that container;
- `Enter` toggles a selected group or entry;
- `Enter` on a field performs that field's action.

Keyboard selection uses a compact blue indicator on the active row's left edge
and survives tree re-rendering caused by expansion or collapse. Switching back
to the mouse removes the keyboard indicator. Non-editable interface text is
not selectable; normal selection remains available inside text inputs and text
areas.

## Field actions

- `Text` and `Secret` fields copy their values through the Rust backend.
- `Secret` fields are masked until their eye control is used.
- `URL` fields open validated `http://` or `https://` destinations in the
  system browser.
- `SSH` fields launch the configured connection in the system terminal. See
  [SSH key design](SSH_KEYS_V2.md) for the complete workflow and security
  model.

The clipboard is cleared after the configured timeout only if it still
contains the value copied by `bunch-of-keys`, so newer clipboard contents are
not deleted.

## Search

Search covers group names, entry names, field labels, and non-masked values.
Masked values are not sent to frontend search.

## Settings and appearance

The settings dialog controls:

- launch at sign-in;
- automatic locking after 1, 5, 15, or 60 minutes of inactivity;
- clipboard clearing after 10, 30, 60, or 120 seconds;
- YAML import into the vault root.

The theme menu is available in every application state. `System` follows live
operating-system appearance changes, while `Light` and `Dark` remain fixed
until another mode is selected.

## Window and tray behavior

The unlocked workspace opens at the application's minimum size of 440 × 480
logical pixels and can be resized up. At narrow widths the search field moves
below the title-bar actions while the minimize and hide-to-tray controls remain
available. Setup and unlock views size themselves to their content.

Closing the window hides it instead of quitting. A left click on the tray icon
shows and focuses the main window. The tray menu provides `Open
bunch-of-keys`, `Lock vault`, and `Quit` actions.

On macOS, `bunch-of-keys` appears in the menu bar. SSH actions open the system
Terminal application, and URL actions use the default browser. Automatic
locking on operating-system screen-lock and suspend notifications is currently
available only on Linux; inactivity locking remains available on both
platforms.

## YAML import

A mapping containing only scalar values becomes an entry. A mapping containing
nested mappings becomes a group. If a mapping contains both, its scalar fields
are placed in an entry named `General` inside that group. Root-level scalar
values are also placed in a root `General` entry.

Field names containing words such as `password`, `token`, `secret`, or
`api-key` are imported as masked `Secret` fields. Labels containing `url` or
`addr` are imported as `URL` fields when their values start with `http://` or
`https://`; other values, including multiline values, become `Text` fields.
The importer sends the selected file contents directly to the backend and does
not create an intermediate copy on disk.

## Data locations

On Linux, the application follows the XDG base directory specification:

```text
$XDG_CONFIG_HOME/bunch-of-keys/config.json
$XDG_DATA_HOME/bunch-of-keys/vaults/<uuid>.bok
```

When those variables are not set, the conventional `~/.config` and
`~/.local/share` locations are used.

On macOS, configuration and vaults are stored under
`~/Library/Application Support/bunch-of-keys/`.
