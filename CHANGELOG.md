# Changelog

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
