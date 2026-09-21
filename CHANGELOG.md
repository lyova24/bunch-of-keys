# Changelog

## 1.5.1 - 2026-09-21

- Added change-aware CI that skips native builds for documentation-only
  updates, caches Cargo artifacts, and runs locked Rust and UI checks.
- Added weekly and dependency-change security checks with RustSec auditing,
  license and source policy enforcement, and grouped Dependabot updates.
- Added synchronized version validation and a manual Debian artifact build
  without automatic releases, tags, or package signing.

## 1.5.0 - 2026-09-21

- Added click-to-toggle group headers and accessible keyboard navigation across
  visible groups, entries, and expanded fields, including copy, browser, and
  SSH field activation.

## 1.4.0 - 2026-09-21

- Added secure SSH connection launching in the system terminal through a
  per-connection, owner-only, in-memory SSH agent with direct argument passing,
  encrypted-key passphrase prompts, bounded lifetime, lock/exit cleanup, and
  persistent failure output so connection errors remain visible; connection
  controls now return to their ready state when the terminal closes, and the
  selected agent key is used consistently across hosts regardless of SSH
  configuration-specific `IdentityFile` rules.

## 1.3.0 - 2026-09-21

- Added structured SSH connection fields and reusable named OpenSSH private
  keys with encrypted vault storage, safe metadata-only frontend views,
  reference-preserving rename and replacement, guarded deletion, validation,
  and backward-compatible schema migration.

## 1.2.1 - 2026-09-21

- Removed the large standalone logo from the unlock screen and tightened the
  heading spacing while preserving the window-header branding.

## 1.2.0 - 2026-09-20

- Added System, Light, and Dark appearance modes, persisted the selected mode,
  followed live operating-system appearance changes in System mode, and kept
  existing explicit Light and Dark preferences compatible.

## 1.1.7 - 2026-09-20

- Reflowed group and entry editors at compact window sizes so names, fields,
  status badges, drag controls, and actions remain readable without overflow,
  allowed unsaved drafts to be dragged directly into their target group, and
  made the last opened or clicked group the default destination for new drafts
  until the user clicks outside that group and its entries.

## 1.1.6 - 2026-09-20

- Replaced oversized group and entry drag snapshots with header-only previews
  that preserve the row width at 105% of its original size across display
  scaling levels and retain translucent drag feedback.

## 1.1.5 - 2026-09-20

- Removed the duplicate Note field type while transparently loading legacy
  Note fields as Text without changing their labels or values.

## 1.1.4 - 2026-09-20

- Kept the in-app minimize and close controls visible at compact window sizes
  and tightened the header without sacrificing accessible actions.
- Centered a compact, capped-width search field between the vault identity and
  the right-side action groups on wide headers.

## 1.1.3 - 2026-09-20

- Made the configured minimum window dimensions the default size for the vault
  workspace while preserving content-based setup and unlock sizing.

## 1.1.2 - 2026-09-20

- Replaced the square native window shadow with a visible, soft CSS shadow that
  follows the rounded app surface on light and dark backgrounds and aligned
  resizing with the visible window edge.

## 1.1.1 - 2026-09-20

- Hid the search placeholder while the field is focused and restored it when
  the empty field loses focus.

## 1.1.0 - 2026-09-17

- Made each displayed field value an accessible copy target and removed the
  separate copy button.
- Added brief inline and toast feedback after copying while keeping reveal and
  edit controls independent.

## 1.0.0 - 2026-09-16

- Replaced the sidebar and group/entry creation dialogs with one compact
  workspace for inline creation, editing, and inspection.
- Added root-level and nested drafts, full read-only entry paths, compact
  collapsed entry rows, and direct drag-and-drop for moving or reordering
  groups and entries with cyclic nesting prevention.
- Matched the workspace across light, dark, desktop, and narrow layouts with
  dense hierarchy lines, compact fields, and consistent icon controls.

## 0.5.0 - 2026-09-16

- Added field-order controls to the entry editor and persisted the selected
  order without changing field identifiers, values, types, or masking.

## 0.4.0 - 2026-09-16

- Collapsed entries by default and added per-entry controls that reveal or
  hide their fields at every group nesting level.

## 0.3.0 - 2026-09-16

- Collapsed all sidebar groups by default and added accessible controls for
  expanding and collapsing nested groups.

## 0.2.1 - 2026-09-16

- Made window dragging reliable by using Tauri's native drag region while
  keeping title-bar controls interactive.

## 0.2.0 - 2026-09-16

- Replaced the GNOME window frame with a compact in-app title bar.
- Made setup and unlock forms the window surface instead of nesting them in a
  second card.
- Added rounded, transparent window edges and a restrained window shadow.
- Added in-app minimize, hide-to-tray, explicit window dragging, and
  edge/corner resize controls.
- Added content-measured startup sizing for setup/unlock and a larger vault
  workspace.
- Reduced the minimum master-password length from 12 to 8 characters.

## 0.1.0 - 2026-09-16

- Initial Linux release with encrypted vaults, a hierarchical credential tree,
  YAML import, tray integration, autostart, auto-lock, and Debian packaging.
