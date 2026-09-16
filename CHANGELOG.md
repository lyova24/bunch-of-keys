# Changelog

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
